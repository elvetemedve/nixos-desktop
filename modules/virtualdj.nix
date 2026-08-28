# Runs VirtualDJ in a dedicated Wine prefix using the wine-vdj flake's
# patched Wine and PipeASIO. VirtualDJ itself is installed into the prefix by
# hand; everything it needs around that -- the PipeASIO driver registration,
# the DDJ-FLX10 driver-name alias, the display DPI -- is applied on each
# start, so the prefix can be rebuilt from scratch without manual setup.
{ pkgs, inputs, username, ... }:
let
  wineVdj = inputs.wine-vdj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  prefix = "/home/${username}/virtualdj";

  virtualdj = pkgs.writeShellApplication {
    name = "virtualdj";
    text = ''
      export WINEPREFIX=${prefix}

      # A rebuilt wine-vdj is a different Nix store path; a wineserver left
      # running from the previous one keeps serving this prefix with stale
      # binaries until it's killed off. Safe here: nothing else uses this
      # prefix's wineserver.
      "${wineVdj}/bin/wineserver" -k || true

      # Stages pipeasio64.dll into the prefix's system32 and registers the
      # CLSID plus HKLM\Software\ASIO\PipeASIO. Without it the .reg imports
      # below leave InprocServer32 naming a file that does not exist, and
      # VirtualDJ -- which stats that path before loading the driver --
      # silently skips it and offers to download one instead. Needs no
      # WINEDLLPATH/PIPEASIO_PREFIX/PATH here: the wine-vdj wrapper carries
      # them. Idempotent: same DLL re-copied, same registration re-run.
      "${wineVdj}/bin/pipeasio-register"

      # Must follow pipeasio-register: it writes InprocServer32 as the bare
      # name that the fullpath .reg corrects, and creates the ASIO list that
      # the FLX10 alias joins. Idempotent: re-importing the same values is a
      # no-op.
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-pipeasio-as-ddj-flx10.reg}
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-pipeasio-fullpath-clsid.reg}
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-hidpi.reg}

      exec "${wineVdj}/bin/wine" 'C:\Program Files\VirtualDJ\virtualdj.exe' "$@"
    '';
  };

  # Opens the same prefix's registry, for inspecting what the .reg imports
  # and PipeASIO actually wrote. Note that edits to the keys the launcher
  # manages -- the ASIO alias, that CLSID's InprocServer32, LogPixels -- do
  # not survive, since `virtualdj` re-imports the .reg files on every start;
  # change those in the .reg files next to this module instead.
  #
  # Deliberately no `wineserver -k` here, unlike `virtualdj`: sharing the
  # wineserver with a running VirtualDJ is the normal case, and killing it
  # would take the running app down with it.
  virtualdj-regedit = pkgs.writeShellApplication {
    name = "virtualdj-regedit";
    text = ''
      export WINEPREFIX=${prefix}

      # "$@" so this also serves the scripted forms, e.g.
      #   virtualdj-regedit /E out.reg 'HKEY_LOCAL_MACHINE\Software\ASIO'
      exec "${wineVdj}/bin/regedit" "$@"
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "virtualdj";
    desktopName = "VirtualDJ";
    exec = "${virtualdj}/bin/virtualdj";
    categories = [ "AudioVideo" "Audio" ];
  };
in
{
  # Microsoft core fonts, published through fontconfig. That is the whole
  # font story: Wine enumerates fontconfig when it initialises a prefix and
  # registers what it finds, so these arrive in the prefix as Arial, Tahoma,
  # Verdana, ... with no per-prefix step.
  #
  # They must not also be symlinked into the prefix's drive_c/windows/Fonts.
  # Wine's fontconfig pass skips families whose files already sit in the
  # Windows font directory, and its scan of that directory does not register
  # them either, so mirroring them there removes every one of these faces
  # rather than adding them -- leaving VirtualDJ to draw skin glyphs such as
  # U+25C4/U+25BA as .notdef boxes.
  fonts.packages = [ pkgs.corefonts ];

  environment.systemPackages = [ virtualdj virtualdj-regedit desktopItem ];
}
