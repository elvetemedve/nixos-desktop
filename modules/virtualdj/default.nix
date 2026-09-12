# Runs VirtualDJ in a dedicated Wine prefix using the wine-vdj flake's
# patched Wine and PipeASIO. VirtualDJ itself is installed into the prefix by
# hand; everything it needs around that -- the PipeASIO driver registration,
# the DDJ-FLX10 driver-name alias, the display DPI -- is applied on each
# start, so the prefix can be rebuilt from scratch without manual setup.
{ pkgs, inputs, username, ... }:
let
  wineVdj = inputs.wine-vdj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  prefix = "/home/${username}/virtualdj";

  # Microsoft's real HLSL compiler, to replace Wine's builtin d3dcompiler_47.
  #
  # VirtualDJ compiles its "source only" visuals through D3DCompile on every
  # load -- 265 of the 720 shaders carry only ShaderToy source, and nothing
  # anywhere caches the compiled result (not the .vdjshader, not Cache/, not
  # cache.db) -- so which implementation answers that call decides the code
  # those shaders actually execute. It really is this DLL that serves them,
  # even though virtualdj.exe neither imports nor names it: the name is built
  # at runtime, so no string search finds it. Confirmed with
  # WINEDEBUG=+loaddll, which shows system32\d3dcompiler_47.dll loaded.
  #
  # Same file and pinned hash winetricks' d3dcompiler_47 verb uses: the copy
  # Mozilla redistributes with fxc2. The URL tracks a branch, so the hash is
  # what actually pins it -- an upstream change fails the build loudly rather
  # than silently swapping the compiler underneath the prefix.
  d3dcompiler47 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47.dll";
    sha256 = "4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3";
  };

  virtualdj = pkgs.writeShellApplication {
    name = "virtualdj";

    # For the missing-SSD prompt below. The desktop entry is the usual way
    # in and it has no terminal, so the graphical prompt is not a fallback
    # here -- it is the path that normally runs.
    # coreutils for the `install` that stages d3dcompiler_47; the script runs
    # under `set -e`, so a missing binary would abort the launch outright.
    runtimeInputs = [ pkgs.zenity pkgs.coreutils ];

    text = ''
      export WINEPREFIX=${prefix}

      # The database, playlists, mappers and settings live on the external
      # SSD (D:\VirtualDJ, pinned by homefolder.reg). With the SSD
      # missing VirtualDJ does not stop -- it falls back to a real and
      # populated internal copy under C:, so the session looks completely
      # normal while every edit lands somewhere that vanishes from view the
      # moment the SSD is back. That is the failure worth guarding: not a
      # crash, but a silent success against the wrong database.
      #
      # This sits ahead of `wineserver -k` and the .reg imports on purpose --
      # declining must leave the prefix, and any wineserver already serving
      # it, untouched.
      #
      # Tested through dosdevices rather than the mount path, so the guard
      # follows the drive mapping instead of duplicating it.
      #
      # Two prompts, because there are two ways in: a terminal, and the
      # desktop entry, which has no stdin to read. With neither a TTY nor a
      # display there is nobody to ask, and an unattended start is exactly
      # the case that must not quietly use the wrong database -- so refuse.
      homeFolder="${prefix}/dosdevices/d:/VirtualDJ"
      if [ ! -d "$homeFolder" ]; then
        warning="The external SSD is not attached.

VirtualDJ will fall back to its internal database on C:. Tracks, playlists
and settings you change will be written there, will not reach the SSD, and
will not be there the next time you start with it attached."

        if [ -t 0 ]; then
          printf '%s\n\n' "$warning" >&2
          read -r -p "Start VirtualDJ anyway? [y/N] " reply || reply=""
          case "$reply" in
            [yY] | [yY][eE][sS]) ;;
            *)
              echo "virtualdj: aborted; external SSD not attached." >&2
              exit 1
              ;;
          esac
        elif [ -n "''${WAYLAND_DISPLAY:-}''${DISPLAY:-}" ]; then
          if ! zenity --question --no-markup --no-wrap --default-cancel \
                 --title "VirtualDJ" \
                 --ok-label "Start anyway" --cancel-label "Cancel" \
                 --text "$warning

Start VirtualDJ anyway?"; then
            echo "virtualdj: aborted; external SSD not attached." >&2
            exit 1
          fi
        else
          echo "virtualdj: external SSD not attached, and no terminal or display to ask on; refusing to start." >&2
          exit 1
        fi
      fi

      # VirtualDJ queries the DXGI swapchain and draws D2D glyph runs on every
      # frame, and Wine's stubs there are plain FIXMEs rather than FIXME_ONCE,
      # so each frame writes several unbuffered lines to stderr. Neither gap
      # affects us: the swapchain's ScanlineOrdering/Scaling fields only matter
      # for interlaced and stretched exclusive-fullscreen modes, and the
      # ignored D2D options are CLIP|ENABLE_COLOR_FONT (text not clipped to its
      # layout box, colour fonts drawn monochrome).
      #
      # fixme-win is the same story for input: VirtualDJ polls
      # NtUserGetKeyboardLayout for another thread's layout, and Wine only
      # tracks a layout for the calling thread, so it answers with
      # "couldn't return keyboard layout for thread NNNN" every time -- 1350
      # lines in one measured session, all identical, all from one thread. It
      # is advisory only; the layout is used for key-name display, and every
      # keystroke and hotkey still works. WINEDEBUG filters by channel and not
      # by function, so this does take the rest of the `win` channel with it;
      # the only other win fixme observed in a full session was
      # RegisterTouchWindow x4, a one-shot that does not apply here
      # (touchScreenMode=no). If a window or input bug ever needs chasing,
      # drop fixme-win from this list for the run.
      #
      # fixme-vkd3d is the largest source by far, and unlike the others it is
      # a single burst rather than a steady drip: ONNX Runtime probes D3D12
      # feature support for every operator as the GPU stem engine starts, and
      # Wine's vkd3d does not implement D3D12_FEATURE_QUERY_META_COMMAND
      # (0x1f), so startup emits ~6400 identical "Unhandled feature 0x1f"
      # lines -- about 6425 of a 6500-line session -- then nothing. The
      # missing feature is real but not fatal: no vendor metacommands means
      # DirectML falls back to its own generic compute shaders instead of
      # NVIDIA's tensor-core kernels, which costs throughput but still runs.
      # Dropping fixme-vkd3d for a run also brings back the genuinely useful
      # one-shots -- EnqueueMakeResident and EnumerateMetaCommands stubs, and
      # the "Push constants size 260 exceeds maximum allowed size 256" notice.
      #
      # Only these four channels' fixmes are silenced, so every other fixme,
      # err and warn still shows.
      export WINEDEBUG=fixme-dxgi,fixme-d2d,fixme-win,fixme-vkd3d,fixme-crypt

      # Split the two graphics APIs across the two GPUs. VirtualDJ's skin is
      # D3D11, which wined3d draws through OpenGL; its GPU stem separation is
      # DirectML on D3D12, which vkd3d runs through Vulkan. Sending both to the
      # eGPU -- what `nvidia-offload virtualdj` does -- spends ~56% of the card
      # and ~2.4 GB/s of Thunderbolt bandwidth on the 4K skin alone, because
      # every frame is rendered on the eGPU and copied back across the tunnel.
      # That halves separation speed: measured 9.3x with the skin on the eGPU,
      # 18.2x with it on the iGPU, against 18-22x on Windows.
      #
      # Restricting only the *Vulkan* loader to the NVIDIA ICD puts DirectML on
      # the eGPU while OpenGL stays on the Intel iGPU, where the skin costs the
      # eGPU nothing. Do not add __NV_PRIME_RENDER_OFFLOAD or
      # __GLX_VENDOR_LIBRARY_NAME here -- those are exactly what drag GL onto
      # the eGPU. Launch `virtualdj` plain, not `nvidia-offload virtualdj`.
      #
      # Guarded so this still works with the eGPU unplugged: with no NVIDIA
      # device, pinning the loader to its ICD would leave Vulkan with no device
      # at all, D3D12 creation would fail, and VirtualDJ would persist
      # <stemsFix>Don't use GPU</stemsFix> into settings.xml -- which is sticky
      # and keeps GPU stems off even after the eGPU comes back.
      nvidiaIcd=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
      if [ -e "$nvidiaIcd" ] && [ -n "$(find /proc/driver/nvidia/gpus -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        export VK_DRIVER_FILES="$nvidiaIcd"
        export VK_ICD_FILENAMES="$nvidiaIcd"  # loaders older than 1.3.207
      fi

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
      "${wineVdj}/bin/wine" regedit /S ${./pipeasio-as-ddj-flx10.reg}
      "${wineVdj}/bin/wine" regedit /S ${./pipeasio-fullpath-clsid.reg}
      "${wineVdj}/bin/wine" regedit /S ${./hidpi.reg}

      # Stage Microsoft's d3dcompiler_47 where the `native` override can find
      # it, then set that override. install rather than cp so the mode is ours
      # whatever was there before -- the prefix already had a stale copy of
      # Wine's own builtin sitting in system32.
      install -Dm644 ${d3dcompiler47} \
        "${prefix}/drive_c/windows/system32/d3dcompiler_47.dll"
      "${wineVdj}/bin/wine" regedit /S ${./d3dcompiler.reg}

      # Clears the old "UseXRandR"="N" that used to live here. It stopped
      # full-screen mode jumping to the TV only by making Wine blind to the
      # TV altogether, which cost the visualisation window its output. What
      # actually keeps full screen on the laptop is the <logicalmonitor>
      # order in ~/.config/monitors.xml; see the comments in the .reg itself.
      "${wineVdj}/bin/wine" regedit /S ${./fullscreen-monitor.reg}

      # Re-pins the data directory to the external SSD. VirtualDJ rewrites
      # this key to its C: default whenever the SSD is missing, and never
      # restores it, so without this a single driveless run would leave
      # every later run reading the stale internal copy. Must stay ahead of
      # the exec below: it only works because it lands before virtualdj.exe
      # reads the key.
      "${wineVdj}/bin/wine" regedit /S ${./homefolder.reg}

      # Makes DXGI report a card VirtualDJ will enable GPU stems on; see the
      # comments in the .reg itself.
      "${wineVdj}/bin/wine" regedit /S ${./gpu-pci-id.reg}

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

  # VirtualDJ's own icon, as winemenubuilder extracted it from virtualdj.exe
  # when the MSI ran. Carried here rather than pointed at in
  # ~/.local/share/icons, because that copy is user state: it is named after
  # a hash (0AAF_virtualdj.0) that winemenubuilder regenerates, so it does
  # not survive reinstalling VirtualDJ or rebuilding the prefix -- which is
  # exactly when the entry must not quietly lose its icon.
  #
  # Installed into hicolor rather than named by absolute path, so the shell
  # picks the size it wants; all four the .exe carries are here.
  virtualdjIcon = pkgs.runCommand "virtualdj-icon" { } ''
    install -Dm444 ${./icons/16x16.png}   $out/share/icons/hicolor/16x16/apps/virtualdj.png
    install -Dm444 ${./icons/32x32.png}   $out/share/icons/hicolor/32x32/apps/virtualdj.png
    install -Dm444 ${./icons/48x48.png}   $out/share/icons/hicolor/48x48/apps/virtualdj.png
    install -Dm444 ${./icons/256x256.png} $out/share/icons/hicolor/256x256/apps/virtualdj.png
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "virtualdj";
    desktopName = "VirtualDJ";
    exec = "${virtualdj}/bin/virtualdj";
    icon = "virtualdj";
    categories = [ "AudioVideo" "Audio" ];

    # WM_CLASS on the main window is virtualdj.exe, for both instance and
    # class. Without this the shell cannot tie the running window back to
    # this entry, and shows a second, generic tile next to the launcher
    # instead of marking this one as running.
    startupWMClass = "virtualdj.exe";
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
  #
  # Korean text (track titles, tags) falls back to fontconfig's default
  # sans-serif otherwise, which has no proper Hangul glyphs and renders as
  # boxes or a bare CJK fallback. Pretendard covers Hangul with a UI-native
  # look; Noto Sans CJK KR is the broader fallback for anything Pretendard
  # doesn't cover (Hanja, mixed CJK).
  #
  # Use the *-static variant, not noto-fonts-cjk-sans: that one ships a
  # single variable-font (.otf.ttc with a "wght" axis) per script. Wine's
  # font engine doesn't instance variable-font weight axes, so it rasterises
  # the raw default master instead -- which renders visibly thinner than the
  # static Latin faces sitting next to it. The static package ships one
  # fixed-weight .ttc per weight (Regular, Bold, ...) that Wine can select
  # directly.
  fonts.packages = [ pkgs.corefonts pkgs.pretendard pkgs.noto-fonts-cjk-sans-static ];

  environment.systemPackages = [ virtualdj virtualdj-regedit desktopItem virtualdjIcon ];
}
