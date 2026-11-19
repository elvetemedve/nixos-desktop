"""Turn DJ.Studio's phrase analysis into VirtualDJ remix points.

DJ.Studio (the Windows app `djstudio` runs under Wine; see default.nix)
splits every analysed track into labelled phrases -- INTRO, VERSE, CHORUS,
BRIDGE, INSTRUMENTAL, OUTRO -- and keeps them as plain JSON, one file per
record, in its data directory:

  Database/audio-library-table/*/<key>     track record: Windows path, file
                                           size, and its structureKey
  Database/track-structures-table/*/<key>  phraseData (seconds and label)
                                           and the beat grid (beatData)

Its studio.db holds only the library index, no phrases. A file DJ.Studio
has more than one record for (opened directly, and imported from
VirtualDJ) is taken from the most recently written structure.

Commands:
  show [FILTER]    print the cleaned phrases of every track whose path or
                   tags contain FILTER (--raw: DJ.Studio's own, uncleaned)
  export [FILTER]  replace those songs' remix points in VirtualDJ's
                   database.xml with the cleaned phrases; only a report of
                   what would change, unless --write is given

Cleaning. DJ.Studio's phrases are often not whole 8-bar blocks, and where
the 8-bar grid lies on either side of an odd one tells which case it is:
  * A lone boundary off the grid, with the next one back on it, is just
    misplaced (9 bars then 7, 3+5, 6+2): it moves to the nearest grid
    line, and a phrase that shrinks to nothing goes.
  * A grid that stays one bar later from some boundary on is a 1-bar fill
    the analysis missed and glued onto the 8n+1-bar phrase before it. It
    is split off as its own FILL phrase, from whichever end of that phrase
    sounds least like its two neighbours (per-beat band energies of the
    audio, decoded with ffmpeg); a close call is noted.
  * Neighbouring phrases with the same label are merged; fills never are.
Anything else stays as DJ.Studio has it, noted. The first and
last phrase are exempt from all of it: they end where the audio file does.
The fill picking is only a tie-break between the two ends of a phrase
DJ.Studio already made one bar too long; scored over a whole track, the
ending and the breakdowns outrank the real fills.

Downbeat. DJ.Studio's bar lines are sometimes a beat off the music, and
every phrase with them. At each boundary the sound 2 beats before is
compared with 2 beats after, at the marked downbeat and up to 2 beats
either side. Where the biggest change lands a beat after (or before) it
at twice as many boundaries, and clearly bigger on average, the bar
lines move by that beat and the cleaning runs again. --no-shift keeps
DJ.Studio's.

Kick check. The cleaned phrases are then held against the kick drum, 8
bars at a time: a block has a kick when its sub-bass (40-100 Hz) is
clearly stronger where the track's kick sits in the beat than in the
rest of it, and not far under the track's usual level. A missing kick
contradicts only some labels:
  * A CHORUS without a kick takes the label of a kick-less VERSE, BRIDGE
    or BREAK beside it, or becomes a BREAK.
  * A kick-less stretch inside an INTRO after its kick has started, or
    inside an OUTRO before its kick comes back, is a BREAK -- which also
    gives the boundary DJ.Studio missed where the kick returns.
  * A kick-less INSTRUMENTAL is only noted.
  * VERSE and BRIDGE are left alone: verses often drop the kick.
A track with a kick in under a fifth of its blocks -- pop with a
half-time beat, say -- has no steady kick to go by and keeps its labels.
Last, repeats: each 8-bar block is compared with the earlier ones in 48
bands per beat, and its nearest, if close enough, is the same music.
DJ.Studio labels repeats inconsistently -- part of a repeated chorus an
INSTRUMENTAL, say -- so where 16 bars or more repeat an earlier stretch
block for block, both stretches take the label most of their blocks
carry. A shorter repeat, or a tie, under different labels is only
noted. Same-label neighbours are merged again at the end. The
thresholds were set on three tracks checked by ear and tried on sixteen
more. --no-kick leaves the whole check out.

Export. Each cleaned phrase becomes a numbered, coloured remix point named
after its label and its length in bars, "Chorus (16)" -- VirtualDJ has
no field for a marker's length, but shows its name and lets a script
read it -- in the colour DJ.Studio shows it in. (On a double-time grid,
High Hopes say, the bars are DJ.Studio's: twice the felt ones.) They are
numbered from 33 up: a numbered remix point is a hot cue as well, and
the HOTCUES pads would otherwise show the first 8 phrases in place of
the DJ's own cues. Every remix point the song had before,
VirtualDJ's own "Break 1"/"End Break 1" markers included, is replaced, so
the export can be re-run. Songs are matched on their Windows path, which
DJ.Studio copies verbatim for tracks imported from VirtualDJ (and both
prefixes map C:\\users\\<user>\\Music to ~/Music), and on their file size.
VirtualDJ keeps the database in memory and writes it back on exit, so
--write refuses while it runs; the file it replaces is kept beside it.

The @NAME@ tokens are substituted by default.nix at build time.
"""

import argparse
import bisect
import glob
import html
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from collections import Counter

import numpy as np

FFMPEG = "@ffmpeg@"  # noqa: E501 -- a store path once substituted
VDJ_DATABASE = "@vdjDatabase@"  # noqa: E501 -- a long path once substituted
DJSTUDIO_PREFIX = "@djstudioPrefix@"

UNIT = 8             # bars per phrase-grid step
FILL = "FILL"        # label of the 1-bar phrases cleaning splits off
FILL_COLOR = "#ffb400"
BREAK = "BREAK"      # label of the kick-less stretches the kick check finds
BREAK_COLOR = "#00a0c8"
CALM = ("VERSE", "BRIDGE", BREAK)  # labels a missing kick does not contradict
CLOSE_CALL = 1.25    # fill picks whose scores are closer are noted "close"
KICK_DB = 3.0        # a block's median on-beat sub-bass contrast with a kick
SUB_DB = 15.0        # ...and its sub-bass at most this far under the usual
KICK_SHARE = 0.2     # a track with a kick in fewer blocks has no steady one
SHIFT_GAIN = 0.1     # a beat-off downbeat must win by this much on average
SAME_DB = 1.9        # blocks closer than this in fine bands: the same music
LENGTH_NOTE = "not a multiple of 8 bars"
# The phrases are numbered from here, as VirtualDJ cues: numbered remix
# points also act as hot cues, and the HOTCUES pads show cues 1-8, so 1-32
# stay free for the DJ's own hot cues and saved loops. The "phrases" pad
# page in ../virtualdj/default.nix (firstCue) must agree.
FIRST_NUM = 33

SONG_RE = re.compile(r'<Song FilePath="([^"]*)"[^>]*>.*?</Song>', re.S)


def load_table(root, table):
    """key -> record, for every JSON file of one sharded table."""
    out = {}
    pattern = os.path.join(root, "Database", table, "*", "**")
    for path in glob.glob(pattern, recursive=True):
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                rec = json.load(f)
            mtime = os.path.getmtime(path)
        except (OSError, ValueError):
            continue
        if isinstance(rec, dict) and "key" in rec:
            rec["_mtime"] = mtime
            out[rec["key"]] = rec
    return out


def wine_to_unix(prefix, winpath):
    """C:\\users\\x\\a.flac -> the real file, via the prefix's dosdevices."""
    if len(winpath) < 3 or winpath[1] != ":":
        return None
    cur = os.path.join(prefix, "dosdevices", winpath[0].lower() + ":")
    for part in winpath[3:].replace("\\", "/").split("/"):
        if not part:
            continue
        nxt = os.path.join(cur, part)
        if not os.path.exists(nxt):  # Windows paths ignore case
            try:
                hits = [e for e in os.listdir(cur)
                        if e.lower() == part.lower()]
            except OSError:
                return None
            if not hits:
                return None
            nxt = os.path.join(cur, hits[0])
        cur = nxt
    return os.path.realpath(cur) if os.path.isfile(cur) else None


class Grid:
    """Seconds <-> bars on a track's beat grid; bar 0 = first phrase."""

    def __init__(self, beats, bpb, origin_time):
        self.t = [b["time"] for b in beats]
        self.bpb = bpb
        self.origin = self._beat(origin_time)
        self.origin_idx = round(self.origin)

    def _beat(self, t):
        i = bisect.bisect_right(self.t, t) - 1
        i = min(max(i, 0), len(self.t) - 2)
        return i + (t - self.t[i]) / (self.t[i + 1] - self.t[i])

    def bar(self, t):
        return (self._beat(t) - self.origin) / self.bpb

    def time(self, bar):
        pos = self.origin + bar * self.bpb
        i = min(max(math.floor(pos), 0), len(self.t) - 2)
        return self.t[i] + (pos - i) * (self.t[i + 1] - self.t[i])


class TrackAudio:
    """A track's audio measured beat by beat on its grid; decoded with
    ffmpeg on first use.

      score(k)  how far bar k stands apart from both neighbours: the RMS
                distance, in dB, of its per-beat energy in 8 bands to the
                previous and to the next bar, whichever is smaller
      kick(k)   bar k's (contrast, level), in dB averaged over its beats:
                how much stronger 40-100 Hz is in the quarter of a beat
                where this track's kick sits than in the rest -- a kick
                drum makes it positive -- and the 30-60 Hz level. Where
                the kick sits is found from the whole track: DJ.Studio's
                beat marks lead the kick by up to some 50 ms.
      block(k)  bars k..k+7 in 48 log-spaced bands per beat, fine enough
                to tell repeated music from merely similar music
    """

    SR = 11025
    EDGES = [30, 60, 120, 250, 500, 1000, 2000, 4000, 5500]
    FINE = np.geomspace(30, 5000, 49)

    SLOTS = 16  # a beat's sub-bass in this many slices, to find the kick

    def __init__(self, audio, grid):
        self.audio = audio
        self.grid = grid
        self.x = None
        self.beats = {}
        self.cache = {}
        self.window = None

    def available(self):
        if self.x is None:
            try:
                pcm = subprocess.run(
                    [FFMPEG, "-v", "error", "-i", self.audio, "-ac", "1",
                     "-ar", str(self.SR), "-f", "f32le", "-"],
                    check=True, capture_output=True).stdout
            except (OSError, subprocess.CalledProcessError):
                pcm = b""
            self.x = np.frombuffer(pcm, dtype=np.float32)
        return len(self.x) > 0

    def _energy(self, part, edges):
        """Energy of part in each band between edges."""
        spec = np.abs(np.fft.rfft(part * np.hanning(len(part)))) ** 2
        freq = np.fft.rfftfreq(len(part), 1 / self.SR)
        return np.array([spec[(freq >= lo) & (freq < hi)].sum() / len(part)
                         + 1e-10 for lo, hi in zip(edges, edges[1:])])

    def _db(self, part, edges):
        return 10 * np.log10(self._energy(part, edges))

    def _beat(self, i):
        """Everything measured on beat i, or None outside the audio."""
        if i not in self.beats:
            t = self.grid.t
            seg = None
            if 0 <= i < len(t) - 1:
                seg = self.x[max(int(t[i] * self.SR), 0):
                             int(t[i + 1] * self.SR)]
            if seg is None or len(seg) < 64:
                self.beats[i] = None
            else:
                n = len(seg) // self.SLOTS
                self.beats[i] = {
                    "bands": self._db(seg, self.EDGES),
                    "fine": self._db(seg, self.FINE),
                    "slots": np.array([
                        self._energy(seg[s * n:(s + 1) * n], [40, 100])[0]
                        for s in range(self.SLOTS)]),
                    "sub": float(self._db(seg, [30, 60])[0]),
                }
        return self.beats[i]

    def _kick_window(self):
        """The quarter-beat slots, from the track's whole sub-bass, in
        which its kick hits; and the rest."""
        if self.window is None:
            beats = [self._beat(i)
                     for i in range(max(self.grid.origin_idx, 0),
                                    len(self.grid.t) - 1)]
            mean = np.mean([b["slots"] for b in beats if b], axis=0)
            q = self.SLOTS // 4
            at = int(np.argmax([sum(mean[(s + j) % self.SLOTS]
                                    for j in range(q))
                                for s in range(self.SLOTS)]))
            win = [(at + j) % self.SLOTS for j in range(q)]
            self.window = (win, [s for s in range(self.SLOTS)
                                 if s not in win])
        return self.window

    def _beats(self, k, n=1):
        """The beats of bars k..k+n-1, or None if any is missing."""
        g = self.grid
        i0 = g.origin_idx + g.bpb * k
        beats = [self._beat(i) for i in range(i0, i0 + g.bpb * n)]
        return None if i0 < 0 or None in beats else beats

    def _bar(self, k):
        if k not in self.cache:
            beats = self._beats(k)
            self.cache[k] = (None if beats is None
                             else np.ravel([b["bands"] for b in beats]))
        return self.cache[k]

    def kick(self, k):
        beats = self._beats(k)
        if beats is None:
            return None
        win, rest = self._kick_window()
        return (float(np.mean([10 * np.log10(np.mean(b["slots"][win])
                                             / np.mean(b["slots"][rest]))
                               for b in beats])),
                float(np.mean([b["sub"] for b in beats])))

    def block(self, k):
        beats = self._beats(k, UNIT)
        return None if beats is None else np.array([b["fine"]
                                                    for b in beats])

    def score(self, k):
        me = self._bar(k)
        if me is None:
            return 0.0
        dists = [float(np.sqrt(np.mean((me - n) ** 2)))
                 for n in (self._bar(k - 1), self._bar(k + 1))
                 if n is not None]
        return min(dists, default=0.0)


def clean(segs, end, scorer):
    """segs: [{"start": bar, "label"}], the first at bar 0."""
    out = [{"start": 0, "label": segs[0]["label"], "notes": []}]
    bounds = [(round(s["start"]), s["label"]) for s in segs[1:]]
    phase = bounds[0][0] % UNIT if bounds else 0

    def place(bar, label, note=None):
        if bar <= out[-1]["start"]:  # the phrase between shrank to nothing
            out[-1]["label"] = label
        else:
            out.append({"start": bar, "label": label, "notes": []})
        if note:
            out[-1]["notes"].append(note)

    for i, (bar, label) in enumerate(bounds):
        if bar >= end:
            break
        shift = (bar - phase) % UNIT
        if shift == 0:
            place(bar, label)
            continue
        nxt = bounds[i + 1][0] % UNIT if i + 1 < len(bounds) else None
        if nxt == phase:  # a lone misplaced boundary
            lo = bar - shift
            target = lo if shift < UNIT - shift else lo + UNIT
            note = f"moved {target - bar:+d} bars"
            if shift * 2 == UNIT:
                note += " (tie)"
            place(target, label, note)
            continue
        if shift == 1:  # a missed 1-bar fill in the phrase ending here
            prev = out[-1]
            first, last = prev["start"], bar - 1
            if first == last:
                prev["notes"].append(f'was {prev["label"]}')
                prev["label"] = FILL
            elif scorer is None or not scorer.available():
                out.append({"start": last, "label": FILL,
                            "notes": ["no audio: guessed last bar"]})
            else:
                sf, sl = scorer.score(first), scorer.score(last)
                note = f"bar {first + 1}: {sf:.1f} vs bar {last + 1}: {sl:.1f}"
                if max(sf, sl) < CLOSE_CALL * min(sf, sl):
                    note += " (close)"
                fill = {"start": first if sf > sl else last, "label": FILL,
                        "notes": [note]}
                if sf > sl:
                    prev["start"] = first + 1
                    out.insert(len(out) - 1, fill)
                else:
                    out.append(fill)
            place(bar, label)
        else:
            signed = shift if shift <= UNIT // 2 else shift - UNIT
            place(bar, label,
                  f"grid shifts {signed:+d} bars here, kept")
        phase = bar % UNIT

    merged = []
    for s in out:
        if merged and s["label"] == merged[-1]["label"] != FILL:
            continue  # the boundary is gone, and its notes with it
        merged.append(s)
    return flag_lengths(merged, end)


def downbeat_shift(phrases, audio):
    """(beats, note): +1 or -1 when the music changes consistently a
    beat after or before DJ.Studio's phrase boundaries -- its bar lines
    then sit a beat off the music -- else 0."""
    g = audio.grid
    offsets = (-2, -1, 0, 1, 2)
    wins, total, n = Counter(), np.zeros(len(offsets)), 0
    for p in phrases[1:]:
        if p["label"] in (FILL, "SILENCE"):
            continue
        b0 = g.origin_idx + g.bpb * int(p["start"])
        change = []
        for off in offsets:  # the sound 2 beats before vs 2 after
            pre = [audio._beat(i) for i in range(b0 + off - 2, b0 + off)]
            post = [audio._beat(i) for i in range(b0 + off, b0 + off + 2)]
            if None in pre + post:
                break
            diff = (np.mean([b["fine"] for b in pre], axis=0)
                    - np.mean([b["fine"] for b in post], axis=0))
            change.append(float(np.sqrt(np.mean(diff ** 2))))
        if len(change) < len(offsets):
            continue
        change = np.array(change)
        wins[offsets[int(np.argmax(change))]] += 1
        total += change / change.max()
        n += 1
    if n < 6:
        return 0, ""
    mean = dict(zip(offsets, total / n))
    for off in (1, -1):
        if (wins[off] >= 2 * max(wins[0], 1)
                and mean[off] - mean[0] >= SHIFT_GAIN):
            return off, (f"markers moved {off:+d} beat: the music changes "
                         f"a beat {'after' if off > 0 else 'before'} "
                         f"DJ.Studio's downbeat at {wins[off]} of {n} "
                         "boundaries")
    return 0, ""


def flag_lengths(phrases, end):
    """Flag the inner phrases that are not whole 8-bar blocks (anew)."""
    for i, s in enumerate(phrases):
        s["notes"] = [n for n in s["notes"] if n != LENGTH_NOTE]
        nxt = phrases[i + 1]["start"] if i + 1 < len(phrases) else end
        inner = 0 < i < len(phrases) - 1
        if inner and s["label"] != FILL and (nxt - s["start"]) % UNIT:
            s["notes"].append(LENGTH_NOTE)
    return phrases


def kick_check(phrases, end, audio):
    """Split and relabel cleaned phrases where the kick drum disagrees
    with DJ.Studio's label; flag repeats that DJ.Studio labelled apart."""
    bars = [audio.kick(k) for k in range(int(end))]
    levels = [b[1] for b in bars if b is not None]
    if not levels:
        return phrases
    floor = float(np.percentile(levels, 90)) - SUB_DB

    def has_kick(lo, hi):
        vals = [b for b in bars[lo:hi] if b is not None]
        if not vals:
            return None
        return bool(np.median([c for c, _ in vals]) >= KICK_DB
                    and np.mean([v for _, v in vals]) >= floor)

    # Each phrase as runs of 8-bar blocks with and without a kick; a
    # remainder under 4 bars belongs to the block before it.
    runs, kicks = [], []
    for n, p in enumerate(phrases):
        stop = phrases[n + 1]["start"] if n + 1 < len(phrases) else end
        edges = [stop]
        if p["label"] != FILL:
            edges = list(range(int(p["start"]), math.ceil(stop), UNIT))[1:]
            if edges and stop - edges[-1] < UNIT // 2:
                edges.pop()
            edges.append(stop)
        lo = p["start"]
        for hi in edges:
            kick = None if p["label"] == FILL else has_kick(
                int(lo), math.ceil(hi))
            if kick is not None:
                kicks.append(kick)
            if runs and runs[-1]["src"] == n and runs[-1]["kick"] == kick:
                runs[-1]["stop"] = hi
            else:
                runs.append({"start": lo, "stop": hi, "label": p["label"],
                             "kick": kick, "src": n, "added": [],
                             "notes": [] if lo != p["start"]
                             else list(p["notes"])})
            lo = hi

    def relabel(r, label, why="no kick"):
        r["added"].append(f'bars {r["start"] + 1}-{math.ceil(r["stop"])}: '
                          f'{why}, was {r["label"]}')
        r["label"] = label

    # Pop with a half-time beat, say: no steady kick to go by, so the
    # labels stay as they are, and only the repeats below are looked at.
    share = sum(kicks) / len(kicks) if kicks else 0.0
    if share < KICK_SHARE:
        runs[0]["added"].append(f"kick in only {share:.0%} of the track; "
                                "kick rules skipped")
        for r in runs:
            r["kick"] = None
    for r in runs:
        if r["kick"] is not False:
            continue
        starts = [s["start"] for s in runs if s["src"] == r["src"]
                  and s["kick"]]
        if (r["label"] == "INTRO" and any(k < r["start"] for k in starts)
                or r["label"] == "OUTRO"
                and any(k > r["start"] for k in starts)):
            relabel(r, BREAK)
        elif r["label"] == "INSTRUMENTAL":
            r["added"].append(f'bars {r["start"] + 1}-{math.ceil(r["stop"])}'
                              ": no kick")
    others = [r for r in runs if r["label"] != FILL]
    for i, r in enumerate(others):
        if r["kick"] is False and r["label"] == "CHORUS":
            calm = [s["label"] for s in others[max(i - 1, 0):i + 2]
                    if s is not r and s["kick"] is False
                    and s["label"] in CALM]
            relabel(r, calm[0] if calm else BREAK)

    # Repeats, in 8-bar blocks: each block's nearest earlier block, if
    # close enough, is the same music.
    blocks = []
    for r in runs:
        cuts = [r["start"]]
        if r["label"] != FILL:
            cuts = list(range(int(r["start"]), math.ceil(r["stop"]), UNIT))
            if len(cuts) > 1 and r["stop"] - cuts[-1] < UNIT // 2:
                cuts.pop()
        for n, lo in enumerate(cuts):
            hi = cuts[n + 1] if n + 1 < len(cuts) else r["stop"]
            blocks.append({"start": lo, "stop": hi, "label": r["label"],
                           "notes": r["notes"] if n == 0 else [],
                           "added": r["added"] if n == 0 else []})
    feats = {}
    for i, b in enumerate(blocks):
        if b["label"] != FILL and b["stop"] - b["start"] >= UNIT:
            f = audio.block(int(b["start"]))
            if f is not None:
                feats[i] = f
    match = {}
    for i in feats:
        dists = [(float(np.sqrt(np.mean((feats[i] - feats[j]) ** 2))), j)
                 for j in feats
                 if blocks[j]["start"] <= blocks[i]["start"] - UNIT]
        if dists and min(dists)[0] < SAME_DB:
            match[i] = min(dists)[1]

    def span(idx):
        return (f'bars {blocks[idx[0]]["start"] + 1}-'
                f'{math.ceil(blocks[idx[-1]]["stop"])}')

    def runs_of(idx):
        """Consecutive block indices, grouped."""
        out = []
        for x in idx:
            if out and x == out[-1][-1] + 1:
                out[-1].append(x)
            else:
                out.append([x])
        return out

    # A stretch repeating an earlier one block for block should carry the
    # same labels. Where 16 bars or more repeat, the label most of the
    # blocks of both stretches have wins; less, or a tie, is only flagged.
    seen = set()
    for i in sorted(match):
        if i in seen:
            continue
        seq = [i]
        while (seq[-1] + 1 in match
               and match[seq[-1] + 1] == match[seq[-1]] + 1):
            seq.append(seq[-1] + 1)
        seen.update(seq)
        pairs = [(k, match[k]) for k in seq]
        votes = Counter(blocks[x]["label"] for p in pairs for x in p)
        top, n = votes.most_common(1)[0]
        if len(seq) >= 2 and n > len(seq):
            for side in (0, 1):  # the later stretch, then the earlier
                twin = {p[side]: p[1 - side] for p in pairs}
                for g in runs_of([x for x in twin
                                  if blocks[x]["label"] != top]):
                    was = "/".join(sorted({blocks[x]["label"] for x in g}))
                    blocks[g[0]]["added"].append(
                        f"{span(g)}: same music as "
                        f"{span([twin[x] for x in g])}, was {was}")
                    for x in g:
                        blocks[x]["label"] = top
        else:
            for g in runs_of([k for k, j in pairs
                              if blocks[k]["label"] != blocks[j]["label"]]):
                js = [match[k] for k in g]
                blocks[g[0]]["added"].append(
                    f"{span(g)} sound like {span(js)} "
                    f'({blocks[js[0]]["label"]})')

    out = []
    for b in blocks:
        if out and b["label"] == out[-1]["label"] != FILL:
            # The boundary is gone and its own notes with it; what the
            # kick check found inside stays.
            out[-1]["notes"] += b["added"]
        else:
            out.append({"start": b["start"], "label": b["label"],
                        "notes": b["notes"] + b["added"]})
    return flag_lengths(out, end)


def build(rec, st, opts):
    pd = st["phraseData"]
    path = ((rec.get("externalRec") or {}).get("fileLocationPath")
            or rec.get("name", ""))
    grid = Grid(st["beatData"], rec.get("beatsPerBar") or 4,
                pd[0]["startTime"])

    def on_grid():
        return grid.bar(pd[-1]["endTime"]), [
            {"start": grid.bar(p["startTime"]), "label": p["label"],
             "notes": []} for p in pd]

    end, raw = on_grid()
    colors = {p["label"]: p.get("color") for p in pd}
    colors[FILL] = FILL_COLOR
    colors[BREAK] = BREAK_COLOR
    audio = wine_to_unix(opts.wineprefix, path)
    if getattr(opts, "raw", False):
        phrases = raw
    else:
        measured = TrackAudio(audio, grid) if audio else None
        phrases = clean(raw, end, measured)
        heard = measured is not None and measured.available()
        if heard and not getattr(opts, "no_shift", False):
            shift, why = downbeat_shift(phrases, measured)
            if shift:  # bar lines a beat over, and everything after anew
                grid.origin += shift
                grid.origin_idx += shift
                measured.cache = {}
                end, raw = on_grid()
                phrases = clean(raw, end, measured)
                phrases[0]["notes"].append(why)
        if heard and not getattr(opts, "no_kick", False):
            phrases = kick_check(phrases, end, measured)
    for i, s in enumerate(phrases):
        nxt = phrases[i + 1]["start"] if i + 1 < len(phrases) else end
        s["bars"] = nxt - s["start"]
        s["startTime"] = grid.time(s["start"])
        s["endTime"] = grid.time(nxt)
        s["color"] = colors.get(s["label"])
    tag = rec.get("tag") or {}
    return {
        "key": rec["key"],
        "path": path,
        "audio": audio,
        "size": rec.get("size"),
        "title": f'{tag.get("artist", "")} - {tag.get("title", "")}',
        "bpm": rec.get("bpm"),
        "phrases": phrases,
    }


def collect(opts):
    library = load_table(opts.djstudio, "audio-library-table")
    structures = load_table(opts.djstudio, "track-structures-table")
    newest = {}
    for key, rec in library.items():
        st = structures.get(rec.get("structureKey") or key)
        if (not st or not st.get("phraseData")
                or len(st.get("beatData") or []) < 2):
            continue
        path = ((rec.get("externalRec") or {}).get("fileLocationPath")
                or rec.get("name", ""))
        tag = rec.get("tag") or {}
        hay = " ".join([path, tag.get("artist", ""), tag.get("title", "")])
        if opts.filter.lower() not in hay.lower():
            continue
        seen = newest.get(path.lower())
        if seen is None or st["_mtime"] > seen[1]["_mtime"]:
            newest[path.lower()] = (rec, st)
    tracks = [build(rec, st, opts) for rec, st in newest.values()]
    return sorted(tracks, key=lambda t: t["path"].lower())


def fmt_time(t):
    m, s = divmod(max(t, 0.0), 60)
    return f"{int(m):d}:{s:05.2f}"


def show(opts):
    tracks = collect(opts)
    if opts.json:
        json.dump(tracks, sys.stdout, indent=2)
        print()
        return
    for t in tracks:
        bpm = f'{round(t["bpm"], 2):g}' if t["bpm"] else "?"
        print(f'\n{t["title"]}  ({bpm} BPM)\n  {t["path"]}')
        print(f'    {"label":<13} {"start":>8} {"bar":>5} {"bars":>6}  notes')
        for p in t["phrases"]:
            print(f'    {p["label"]:<13} {fmt_time(p["startTime"]):>8} '
                  f'{round(p["start"] + 1, 2):>5g} '
                  f'{round(p["bars"], 2):>6g}  ' + "; ".join(p["notes"]))


def remix_pois(phrases):
    pois = []
    for num, p in enumerate(phrases, FIRST_NUM):
        try:
            rgb = int((p["color"] or "").lstrip("#"), 16) & 0xFFFFFF
        except ValueError:
            rgb = 0xFFFFFF
        # The length is in the name: VirtualDJ shows a remix point's name
        # (and lets a script read it) but has no field for its length.
        name = html.escape(f'{p["label"].title()} ({round(p["bars"])})')
        pos = max(p["startTime"], 0.0)
        pois.append(f'<Poi Name="{name}" Pos="{pos:.6f}" Num="{num}" '
                    f'Color="{0xFF000000 | rgb}" Type="remix" />')
    return pois


def rewrite_song(block, pois):
    """Swap a <Song> block's remix points for pois; keep all else."""
    lines = block.split("\n")
    kept, removed = [], []
    for line in lines:
        poi = line.lstrip().startswith("<Poi ")
        if poi and 'Type="remix"' in line:
            name = re.search(r'Name="([^"]*)"', line)
            removed.append(html.unescape(name.group(1)) if name else "?")
        else:
            kept.append(line)
    indent = re.match(r"\s*", lines[1]).group(0) if len(lines) > 1 else ""
    after = [i for i, line in enumerate(kept)
             if line.lstrip().startswith("<Poi ")]
    if after:
        at = after[-1] + 1
    else:
        at = next(i for i, line in enumerate(kept)
                  if line.lstrip().startswith(("<Link", "</Song>")))
    kept[at:at] = [indent + p for p in pois]
    return "\n".join(kept), removed


def vdj_running():
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                if b"virtualdj.exe" in f.read().lower():
                    return True
        except OSError:
            continue
    return False


def export(opts):
    db = opts.database
    if not os.path.isfile(db):
        sys.exit(f"djstudio-phrases: no VirtualDJ database at {db}\n"
                 "Is the external SSD attached? --database picks another.")
    if opts.write and vdj_running():
        sys.exit("djstudio-phrases: VirtualDJ is running; close it first. "
                 "It writes its in-memory database back on exit, over "
                 "whatever this export would write.")
    with open(db, encoding="utf-8", newline="") as f:
        text = f.read()
    songs = {}
    for m in SONG_RE.finditer(text):
        songs.setdefault(html.unescape(m.group(1)).lower(), m)

    edits = []
    for t in collect(opts):
        m = songs.get(t["path"].lower())
        if m is None:
            print(f'skip  {t["title"]}: not in this database')
            continue
        size = re.search(r'FileSize="(\d+)"', m.group(0).split(">", 1)[0])
        if t["size"] and size and int(size.group(1)) != t["size"]:
            print(f'skip  {t["title"]}: DJ.Studio analysed a '
                  f'{t["size"]}-byte file, VirtualDJ has '
                  f'{size.group(1)} bytes')
            continue
        block, removed = rewrite_song(m.group(0), remix_pois(t["phrases"]))
        edits.append((m.start(), m.end(), block))
        print(f'song  {t["title"]}: {len(t["phrases"])} remix points'
              + (f', replacing {len(removed)} ({", ".join(removed)})'
                 if removed else ""))

    if not opts.write:
        print("\nNothing written; add --write to apply.")
        return
    if not edits:
        return
    for start, end, block in sorted(edits, reverse=True):
        text = text[:start] + block + text[end:]
    try:
        ET.fromstring(text)
    except ET.ParseError as e:
        sys.exit(f"djstudio-phrases: result would not parse ({e}); "
                 "nothing written.")

    backup = f'{db}.{time.strftime("%Y%m%d-%H%M%S")}.bak'
    shutil.copyfile(db, backup)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(db), prefix=".database.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(db).st_mode & 0o7777)
        except OSError:
            pass  # e.g. a filesystem without Unix modes
        os.replace(tmp, db)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    print(f"\nWrote {len(edits)} songs to {db}\nPrevious version: {backup}")


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("filter", nargs="?", default="",
                        help="only tracks whose path or tags contain this")
    common.add_argument("--djstudio",
                        default=os.path.expanduser("~/Music/DJ.Studio"),
                        help="DJ.Studio's data directory")
    common.add_argument("--wineprefix", default=DJSTUDIO_PREFIX,
                        help="DJ.Studio's Wine prefix, to find the audio "
                        "(default: %(default)s)")
    common.add_argument("--no-kick", action="store_true",
                        help="skip the kick check after cleaning")
    common.add_argument("--no-shift", action="store_true",
                        help="keep DJ.Studio's downbeats even where the "
                        "music changes a beat off them")
    ap = argparse.ArgumentParser(
        prog="djstudio-phrases",
        description="Turn DJ.Studio's phrases into VirtualDJ remix points.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show", parents=[common],
                       help="print the cleaned phrases")
    s.add_argument("--raw", action="store_true",
                   help="DJ.Studio's own phrases, uncleaned")
    s.add_argument("--json", action="store_true")
    e = sub.add_parser("export", parents=[common],
                       help="write them as VirtualDJ remix points")
    e.add_argument("--database", default=VDJ_DATABASE,
                   help="VirtualDJ's database.xml (default: %(default)s)")
    e.add_argument("--write", action="store_true",
                   help="apply the changes instead of only listing them")
    opts = ap.parse_args()
    if opts.cmd == "show":
        show(opts)
    else:
        export(opts)


if __name__ == "__main__":
    main()
