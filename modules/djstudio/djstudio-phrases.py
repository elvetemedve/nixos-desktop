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
    audio, decoded with ffmpeg). Close calls are flagged "check".
  * Neighbouring phrases with the same label are merged; fills never are.
Anything else stays as DJ.Studio has it, flagged "check". The first and
last phrase are exempt from all of it: they end where the audio file does.
The fill picking is only a tie-break between the two ends of a phrase
DJ.Studio already made one bar too long; scored over a whole track, the
ending and the breakdowns outrank the real fills.

Export. Each cleaned phrase becomes a numbered, coloured remix point named
after its label -- the shape VirtualDJ's POI editor gives one -- in the
colour DJ.Studio shows it in. Every remix point the song had before,
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

import numpy as np

FFMPEG = "@ffmpeg@"  # noqa: E501 -- a store path once substituted
VDJ_DATABASE = "@vdjDatabase@"  # noqa: E501 -- a long path once substituted
DJSTUDIO_PREFIX = "@djstudioPrefix@"

UNIT = 8             # bars per phrase-grid step
FILL = "FILL"        # label of the 1-bar phrases cleaning splits off
FILL_COLOR = "#ffb400"
CLOSE_CALL = 1.25    # fill picks whose scores are closer get "check"

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


class BarScorer:
    """How far a bar stands apart from both neighbours: the RMS distance,
    in dB, of its per-beat energy in 8 bands to the previous and to the
    next bar, whichever is smaller. The audio is decoded on first use."""

    SR = 11025
    EDGES = [30, 60, 120, 250, 500, 1000, 2000, 4000, 5500]

    def __init__(self, audio, grid):
        self.audio = audio
        self.grid = grid
        self.x = None
        self.cache = {}

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

    def _beat(self, i):
        t = self.grid.t
        seg = self.x[max(int(t[i] * self.SR), 0):int(t[i + 1] * self.SR)]
        if len(seg) < 64:
            return None
        spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
        freq = np.fft.rfftfreq(len(seg), 1 / self.SR)
        return [10 * np.log10(spec[(freq >= lo) & (freq < hi)].sum()
                              / len(seg) + 1e-10)
                for lo, hi in zip(self.EDGES, self.EDGES[1:])]

    def _bar(self, k):
        if k not in self.cache:
            g = self.grid
            i0 = g.origin_idx + g.bpb * k
            rows = None
            if 0 <= i0 and i0 + g.bpb < len(g.t):
                rows = [self._beat(i) for i in range(i0, i0 + g.bpb)]
                if any(r is None for r in rows):
                    rows = None
            self.cache[k] = None if rows is None else np.ravel(rows)
        return self.cache[k]

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
                note += " (tie, check)"
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
                            "notes": ["no audio: guessed last bar (check)"]})
            else:
                sf, sl = scorer.score(first), scorer.score(last)
                note = f"bar {first + 1}: {sf:.1f} vs bar {last + 1}: {sl:.1f}"
                if max(sf, sl) < CLOSE_CALL * min(sf, sl):
                    note += " (close, check)"
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
                  f"grid shifts {signed:+d} bars here, kept (check)")
        phase = bar % UNIT

    merged = []
    for s in out:
        if merged and s["label"] == merged[-1]["label"] != FILL:
            continue  # the boundary is gone, and its notes with it
        merged.append(s)
    for i, s in enumerate(merged):
        nxt = merged[i + 1]["start"] if i + 1 < len(merged) else end
        inner = 0 < i < len(merged) - 1
        if inner and s["label"] != FILL and (nxt - s["start"]) % UNIT:
            s["notes"].append("not a multiple of 8 bars (check)")
    return merged


def build(rec, st, opts):
    pd = st["phraseData"]
    path = ((rec.get("externalRec") or {}).get("fileLocationPath")
            or rec.get("name", ""))
    grid = Grid(st["beatData"], rec.get("beatsPerBar") or 4,
                pd[0]["startTime"])
    end = grid.bar(pd[-1]["endTime"])
    raw = [{"start": grid.bar(p["startTime"]), "label": p["label"],
            "notes": []} for p in pd]
    colors = {p["label"]: p.get("color") for p in pd}
    colors[FILL] = FILL_COLOR
    audio = wine_to_unix(opts.wineprefix, path)
    if getattr(opts, "raw", False):
        phrases = raw
    else:
        scorer = BarScorer(audio, grid) if audio else None
        phrases = clean(raw, end, scorer)
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
        print(f'\n{t["title"]}  ({t["bpm"]} BPM)\n  {t["path"]}')
        print(f'    {"label":<13} {"start":>8} {"bar":>5} {"bars":>6}  notes')
        for p in t["phrases"]:
            print(f'    {p["label"]:<13} {fmt_time(p["startTime"]):>8} '
                  f'{round(p["start"] + 1, 2):>5g} '
                  f'{round(p["bars"], 2):>6g}  ' + "; ".join(p["notes"]))


def remix_pois(phrases):
    pois = []
    for num, p in enumerate(phrases, 1):
        try:
            rgb = int((p["color"] or "").lstrip("#"), 16) & 0xFFFFFF
        except ValueError:
            rgb = 0xFFFFFF
        name = html.escape(p["label"].title())
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
        checks = sum("check" in n for p in t["phrases"] for n in p["notes"])
        print(f'song  {t["title"]}: {len(t["phrases"])} remix points'
              + (f', replacing {len(removed)} ({", ".join(removed)})'
                 if removed else "")
              + (f'; {checks} to check, see `show`' if checks else ""))

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
