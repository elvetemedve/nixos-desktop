# Runs DJ.Studio in its own Wine prefix (~/djstudio) with the wine-vdj
# flake's patched Wine -- the same build VirtualDJ runs on, rather than a
# second Wine on the machine. The prefix is kept apart from VirtualDJ's so
# neither app's registry tweaks reach the other. DJ.Studio itself is
# installed into it from its official setup .exe with
# `djstudio-install <file.exe>`.
#
#   djstudio                  start DJ.Studio (or hand it a djstudio:// link)
#   djstudio-install <exe>    install or update it
#   djstudio-phrases ...      export its phrase analysis to VirtualDJ
#
# Two things stop DJ.Studio's Windows build from working under Wine as is;
# both are handled here rather than in the prefix, so a prefix rebuilt from
# scratch needs no manual setup:
#
#   * Its electron-builder installer checks whether DJ.Studio is running by
#     asking powershell.exe, and Wine's powershell.exe is a stub that exits 0
#     -- which the check reads as "running" -- so every install, update and
#     uninstall pops "DJ.Studio cannot be closed" and aborts. See
#     dllOverrides below.
#
#   * Signing in happens in the browser, which ends on a djstudio:// link
#     that only Windows knows how to open. The desktop entry claims
#     x-scheme-handler/djstudio, and `djstudio <link>` passes it to the
#     running app.
{ pkgs, inputs, username, ... }:
let
  wineVdj = inputs.wine-vdj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  prefix = "/home/${username}/djstudio";

  # VirtualDJ's prefix, for the database djstudio-phrases writes to; must
  # match `prefix` in ../virtualdj/default.nix.
  vdjPrefix = "/home/${username}/virtualdj";

  exe = ''C:\Program Files\DJ.Studio\DJ.Studio.exe'';

  # Exported by the launcher and the installer alike.
  #
  # The 32-bit powershell.exe disabled: the installer decides whether
  # DJ.Studio is running from the exit code of
  #   powershell -C "if ((Get-CimInstance Win32_Process | ? { $_.Path...
  #                    .StartsWith('C:\Program Files\DJ.Studio') }).Count
  #                    -gt 0) { exit 0 } else { exit 1 }"
  # where 0 means "running". Wine's builtin answers 0 to anything, so the
  # installer always believes the app is open, tries to kill it, and gives
  # up. Disabled, powershell.exe fails to start at all (exit 6 via cmd),
  # and any non-zero result reads as "not running". This stands in for a
  # stub that exits 1, without swapping files in the prefix. The real
  # check it disables is replaced by the pgrep in djstudio-install.
  #
  # Only the 32-bit copy, by its full path. The installer, and the old
  # version's uninstaller it runs, are 32-bit NSIS programs whose
  # $SYSDIR\WindowsPowerShell resolves to syswow64. DJ.Studio itself is
  # 64-bit and asks the system32 copy once a minute whether Windows is
  # saving power: the builtin's empty answer with exit 0 keeps it quiet,
  # while a powershell.exe that fails to start costs a stack trace on the
  # console every time. (A per-program exception under AppDefaults cannot
  # make this split: Wine settles a disabled main exe before those apply.)
  #
  # It is set for the app as well, not only for djstudio-install: the
  # in-app updater re-runs this same installer, and the uninstaller the
  # installer runs for the old version asks the same question; both
  # inherit the environment of whoever started them.
  #
  # winemenubuilder.exe=d: the installer's shortcuts would make Wine write
  # its own desktop entries and icons under ~/.local/share -- a second
  # DJ.Studio entry next to the one below, that calls a bare `wine` which
  # is not on PATH. Set for the app too, for the same updater reason.
  dllOverrides = ''C:\windows\syswow64\WindowsPowerShell\v1.0\powershell.exe=d;winemenubuilder.exe=d'';

  # For `pgrep -if`. Wine processes show their Windows command line, so this
  # matches the app and its helpers (DJ.Studio.exe --type=renderer, ...),
  # but not the "DJ.Studio Setup x.y.z.exe" installer. Anchored, so a shell
  # or editor that merely mentions the name does not count as the app.
  runningPattern = ''^C:\\Program Files\\DJ\.Studio\\DJ\.Studio\.exe'';

  djstudio = pkgs.writeShellApplication {
    name = "djstudio";
    runtimeInputs = [ pkgs.procps ];
    text = ''
      export WINEPREFIX=${prefix}

      # fixme-all rather than -all: -all also silences the err channel,
      # where "cannot open display" lands, and turns a failed start into a
      # few processes with no window and nothing in the log to say why.
      export WINEDEBUG="''${WINEDEBUG:-fixme-all}"

      export WINEDLLOVERRIDES="${dllOverrides}"

      if [ ! -f "${prefix}/drive_c/Program Files/DJ.Studio/DJ.Studio.exe" ]; then
        echo "djstudio: not installed in ${prefix}; run: djstudio-install <DJ.Studio Setup.exe>" >&2
        exit 1
      fi

      # With DJ.Studio already open, this run is a second instance: Electron's
      # single-instance lock (which works under Wine) forwards its arguments
      # -- the djstudio:// sign-in link, when a browser calls this -- to the
      # running one and quits. Only a fresh start gets the housekeeping
      # below; the wineserver -k would take the running app down with it.
      running=""
      if pgrep -if '${runningPattern}' >/dev/null; then
        running=1
      fi

      # DJ.Studio's startup code logs to the console right away, and Node
      # inside it dies on that first message ("A JavaScript error occurred
      # in the main process ... open EBADF") when its stdout or stderr is a
      # socket -- which is what GNOME and the browser give the programs they
      # start: their output goes to systemd's journal. A second instance
      # dies before it passes its sign-in link on. A terminal works, as does
      # a regular file, so any other output goes to a log file instead:
      # started afresh on a fresh start, appended to by second instances.
      log="${prefix}/djstudio.log"
      for fd in 1 2; do
        if [ ! -t "$fd" ] && [ ! -f "/proc/$$/fd/$fd" ]; then
          if [ -n "$running" ]; then
            exec >>"$log" 2>&1
          else
            exec >"$log" 2>&1
          fi
          break
        fi
      done

      if [ -z "$running" ]; then
        # A rebuilt wine-vdj is a different store path, and a wineserver
        # left from the previous one would keep serving the prefix with
        # stale binaries.
        "${wineVdj}/bin/wineserver" -k || true

        # The display DPI VirtualDJ uses too (200%, for the laptop panel);
        # imported on every start, so a rebuilt prefix gets it as well.
        "${wineVdj}/bin/wine" regedit /S ${../virtualdj/hidpi.reg}

        # The power plan DJ.Studio polls for; see the .reg itself.
        "${wineVdj}/bin/wine" regedit /S ${./power-scheme.reg}
      fi

      # Wine's X11 driver (XWayland), which is what DJ.Studio was evaluated
      # on; the winewayland patches in wine-vdj were made for VirtualDJ.
      exec "${wineVdj}/bin/wine" '${exe}' "$@"
    '';
  };

  # Installs (or updates) DJ.Studio from its setup .exe into the same prefix,
  # with the same Wine and overrides as the launcher.
  #
  #   djstudio-install ~/Downloads/'DJ.Studio Setup 5.0.11.exe'
  #   djstudio-install --quiet file.exe   # unattended (NSIS /S)
  djstudio-install = pkgs.writeShellApplication {
    name = "djstudio-install";
    runtimeInputs = [ pkgs.coreutils pkgs.procps ];
    text = ''
      usage() {
        echo "usage: djstudio-install [--quiet] <DJ.Studio Setup x.y.z.exe>" >&2
        exit 1
      }

      quiet=""
      if [ "''${1:-}" = "--quiet" ]; then
        quiet=1
        shift
      fi
      [ "$#" -eq 1 ] || usage
      if [ ! -f "$1" ] || [ ! -r "$1" ]; then
        echo "djstudio-install: not a readable file: $1" >&2
        exit 1
      fi
      setup=$(realpath "$1")

      export WINEPREFIX=${prefix}
      export WINEDEBUG="''${WINEDEBUG:-fixme-all}"
      export WINEDLLOVERRIDES="${dllOverrides}"

      # The installer's own running-app check is disabled by the override
      # above, so this is the one that counts: replacing files under a
      # running DJ.Studio would leave a broken install. The wineserver -k
      # below would also take it down.
      if pgrep -if '${runningPattern}' >/dev/null; then
        echo "djstudio-install: DJ.Studio is running; close it first." >&2
        exit 1
      fi

      # Same reason as in `djstudio`: a wineserver from a previous wine-vdj
      # build would serve the prefix with stale binaries.
      "${wineVdj}/bin/wineserver" -k || true

      # Creates the prefix if it does not exist yet, or updates it to this
      # Wine; then the DPI, so the installer's own window is readable.
      "${wineVdj}/bin/wineboot" -u
      "${wineVdj}/bin/wine" regedit /S ${../virtualdj/hidpi.reg}

      # wine returns when the installer process exits; it waits for the old
      # version's uninstaller itself. No `wineserver -w` here, unlike
      # virtualdj-install: if the finish page starts DJ.Studio, that would
      # wait for the app to be closed again.
      if [ -n "$quiet" ]; then
        "${wineVdj}/bin/wine" "$setup" /S
      else
        "${wineVdj}/bin/wine" "$setup"
      fi

      if [ ! -f "${prefix}/drive_c/Program Files/DJ.Studio/DJ.Studio.exe" ]; then
        echo "djstudio-install: install did not produce ${exe}" >&2
        exit 1
      fi
      echo "DJ.Studio installed. Start it with: djstudio"
    '';
  };

  # What it reads, how it cleans the phrases up and what it writes is in the
  # docstring of djstudio-phrases.py.
  #
  # The database it writes by default is the one on the SSD -- the same
  # D:\VirtualDJ that the VirtualDJ launcher guards -- and not the C:
  # fallback copy a driveless session runs on; --database points it
  # elsewhere. A missing SSD is therefore an error rather than a silent
  # export into the fallback, for the same reason the launcher asks before
  # starting without it. Through VirtualDJ's dosdevices, so the default
  # follows its D: mapping rather than duplicating the SSD's mount point.
  #
  # ffmpeg decodes the audio when a missed 1-bar fill has to be placed;
  # headless, since only decoding is needed.
  djstudio-phrases = pkgs.writers.writePython3Bin "djstudio-phrases"
    {
      libraries = [ pkgs.python3Packages.numpy ];
    }
    (builtins.replaceStrings
      [ "@ffmpeg@" "@vdjDatabase@" "@djstudioPrefix@" ]
      [
        "${pkgs.ffmpeg-headless}/bin/ffmpeg"
        "${vdjPrefix}/dosdevices/d:/VirtualDJ/database.xml"
        prefix
      ]
      (builtins.readFile ./djstudio-phrases.py));

  # DJ.Studio's own icon, every size winemenubuilder extracted from
  # DJ.Studio.exe (unchanged between 4.2 and 5.0). Carried here because
  # winemenubuilder is off (above), and its copies are hash-named user state.
  djstudioIcon = pkgs.runCommand "djstudio-icon" { } ''
    for size in 16 24 32 48 64 96 256; do
      install -Dm444 ${./icons}/''${size}x''${size}.png \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/djstudio.png"
    done
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "djstudio";
    desktopName = "DJ.Studio";
    exec = "${djstudio}/bin/djstudio %u";
    icon = "djstudio";
    categories = [ "AudioVideo" "Audio" ];

    # The sign-in hand-off: the browser opens djstudio://app/handoff?code=...
    # once the login completes, and that link has to reach the app.
    mimeTypes = [ "x-scheme-handler/djstudio" ];

    # WM_CLASS of the main window, so the shell ties the running window to
    # this entry instead of showing a second, generic one.
    startupWMClass = "dj.studio.exe";
  };
in
{
  environment.systemPackages = [ djstudio djstudio-install djstudio-phrases desktopItem djstudioIcon ];

  # Explicit, so the browser opens sign-in links without asking which app
  # should; home-manager's mimeapps.list has no entry to override it.
  xdg.mime.defaultApplications."x-scheme-handler/djstudio" = "djstudio.desktop";
}
