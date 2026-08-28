{
  description = ''
    Patched Wine + PipeASIO, built for running VirtualDJ with the
    AlphaTheta/Pioneer DDJ-FLX10 controller.

    Five Wine patches (dropped once merged upstream — see patches/README.md).
    Three fix MIDI device identification and ASIO audio-endpoint
    identification, which VirtualDJ needs to auto-recognise the controller;
    the fourth fixes shell32 drive attributes, without which VirtualDJ's
    Local Music → Drives folder lists nothing; the fifth is wine-staging's
    wined3d swapchain fix, without which the skin renders too dark.
    PipeASIO (https://github.com/M0n7y5/pipeasio) provides a low-latency
    ASIO-to-PipeWire audio driver, built here against this same Wine so its
    winelib PE/unix split stays ABI-consistent with it.

    To move to a new Wine release, bump the `ref` on the `wine-src` input
    below — its version number is read from the checkout's own VERSION file,
    so there's nothing else to change. To move to a new PipeASIO release,
    bump the `ref` on `pipeasio-src`; the `pipeasio` derivation deliberately
    carries no separate `version` attribute, since PipeASIO's build exposes
    no machine-readable version marker to derive one from and the `ref`
    above is already the single source of truth. Either way, relock with
    `nix flake lock --update-input wine-src` (or `pipeasio-src`).
  '';

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    wine-src = {
      url = "github:wine-mirror/wine?ref=wine-11.16";
      flake = false;
    };

    pipeasio-src = {
      url = "github:M0n7y5/pipeasio?ref=v1.5.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, wine-src, pipeasio-src, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Wine's VERSION file reads "Wine version X.Y\n" — the one place this
      # flake's Wine version is declared; everywhere else reads it from here.
      wineVersion =
        builtins.head (builtins.match "Wine version ([0-9.]+)\n"
          (builtins.readFile "${wine-src}/VERSION"));

      wine-base = pkgs.wineWow64Packages.full.overrideAttrs (old: {
        version = wineVersion;
        src = wine-src;

        # `.full`, not `.staging`: Staging's patches are tightly coupled to
        # one upstream commit and likely break on a version bump.

        # nixpkgs' own device-paths patch is already applied in wine-src
        # past 11.0; drop it here so the version bump doesn't fail on it.
        patches = (builtins.filter
          (p: !(pkgs.lib.hasInfix "add-dll-accept-device-paths" (toString p)))
          old.patches) ++ [
          ./patches/winealsa-midi-deviceinterface.patch
          ./patches/winmm-midiinmessage-deviceid.patch
          ./patches/mmdevapi-deviceinterface-path.patch
          ./patches/shell32-drive-canrename.patch
          ./patches/0003-wined3d-fix-vk-swapchain-rendering-too-dark-by-suppo.patch
        ];
      });

      # Built against wine-base's own winegcc/winebuild/widl, so bumping
      # wine-base above forces a pipeasio rebuild automatically.
      pipeasio = pkgs.stdenv.mkDerivation {
        # `name`, not `pname`+`version`: without a version to pair with
        # `pname`, mkDerivation exposes no `.name` attribute at all.
        name = "pipeasio";
        src = pipeasio-src;

        # wrapQtAppsHook: pipeasio-settings is a real Qt6 GUI app, so it
        # needs wrapping with the right plugin/QML search paths.
        nativeBuildInputs = with pkgs; [ cmake ninja pkg-config wine-base qt6.wrapQtAppsHook ];
        buildInputs = with pkgs; [ pipewire qt6.qtbase ];

        # Wine 10+ needs pipeasio.dll(.so) symlinks alongside pipeasio64.*;
        # add them if the project's own install() doesn't already.
        postInstall = ''
          winDir=$out/lib/wine/x86_64-windows
          unixDir=$out/lib/wine/x86_64-unix

          if [ -e "$winDir/pipeasio64.dll" ] && [ ! -e "$winDir/pipeasio.dll" ]; then
            ln -s pipeasio64.dll "$winDir/pipeasio.dll"
          fi
          if [ -e "$unixDir/pipeasio64.dll.so" ] && [ ! -e "$unixDir/pipeasio.dll.so" ]; then
            ln -s pipeasio64.dll.so "$unixDir/pipeasio.dll.so"
          fi
        '';
      };
    in
    {
      packages.${system} = {
        inherit wine-base pipeasio;

        # Patched Wine with PipeASIO merged into its own lib/wine tree, with
        # every Wine entry point wrapped to put WINEDLLPATH on that tree.
        #
        # The wrapper is what makes PipeASIO loadable. nixpkgs' Wine wrapper
        # hard-codes WINELOADER to wine-base's own store path, and Wine derives
        # its builtin-DLL directory from that loader, so it searches
        # wine-base's lib/wine, which holds no PipeASIO. WINEDLLPATH is the one
        # DLL search path additive to the loader's own, so it is what brings
        # this joined tree into scope.
        #
        # Wrapping also leaves bin/wine a real file rather than a symlink into
        # wine-base, so pipeasio-register's `readlink -f "$(command -v wine)"`
        # probe for Wine's library directory lands in this tree too: it finds
        # the PipeASIO install with no PIPEASIO_PREFIX set.
        default = pkgs.symlinkJoin {
          name = "wine-vdj";
          paths = [ wine-base pipeasio ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            # Every entry point needs its own wrapper, not just `wine`. Wine
            # picks which program to run from argv[0] -- that is what makes
            # bin/{wineboot,regedit,winepath,...} work as symlinks to bin/wine
            # -- and a `#!` wrapper cannot forward argv[0]: the kernel drops it
            # and bash resets $0 to the wrapper's own path. Each wrapper
            # therefore targets the *same-named* path under wine-base, which is
            # what keeps $0, and with it the program selection, intact.
            for path in ${wine-base}/bin/*; do
              prog=$(basename "$path")
              target=$(readlink "$path" || echo "$prog")
              if [ "$prog" != wine ] && [ "$target" != wine ]; then continue; fi
              rm -f "$out/bin/$prog"
              makeWrapper "$path" "$out/bin/$prog" \
                --prefix WINEDLLPATH : "$out/lib/wine"
            done

            # pipeasio-register shells out to `wine` and `wineboot` by bare
            # name; put this tree's wrapped copies ahead of anything else on
            # PATH so it cannot register against some other Wine.
            rm -f "$out/bin/pipeasio-register"
            makeWrapper "${pipeasio}/bin/pipeasio-register" \
              "$out/bin/pipeasio-register" --prefix PATH : "$out/bin"
          '';
        };
      };
    };
}
