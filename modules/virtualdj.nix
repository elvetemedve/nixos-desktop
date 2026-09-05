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
      export WINEDEBUG=fixme-dxgi,fixme-d2d,fixme-win,fixme-vkd3d

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
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-pipeasio-as-ddj-flx10.reg}
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-pipeasio-fullpath-clsid.reg}
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-hidpi.reg}

      # Makes DXGI report a card VirtualDJ will enable GPU stems on; see the
      # comments in the .reg itself.
      "${wineVdj}/bin/wine" regedit /S ${./virtualdj-gpu-pci-id.reg}

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
