# Patches

Seven local patches plus one carried from wine-staging. All apply cleanly with
`patch -p1` against the pinned `wine-src` (currently Wine 11.21).

- `winealsa-midi-deviceinterface.patch` — `dlls/winealsa.drv/alsamidi.c`.
  Derives USB vid/pid/interface-number from the ALSA sequencer client and
  answers `DRV_QUERYDEVICEINTERFACE[SIZE]`, so a MIDI port can be identified
  by VID/PID at all. Not filed upstream yet.

- `winmm-midiinmessage-deviceid.patch` — `dlls/winmm/winmm.c`. Five-line fix
  so `midiInMessage()` falls back to treating its handle as a device id, the
  same way `midiOutMessage()` already does — without it, MIDI input never
  gets an interface path even after the patch above. Not filed upstream yet.

- `mmdevapi-deviceinterface-path.patch` — `dlls/mmdevapi/devenum.c`. Stores
  the device path `winepulse.drv` already computes (carrying real USB
  vid/pid) under `deviceinterface_key`, instead of a bare endpoint GUID.
  General-purpose — fixes every USB/HDAUDIO audio endpoint for any
  application, not just this controller. Not filed upstream yet.

- `shell32-drive-canrename.patch` — `dlls/shell32/shlfolder.c`. One line:
  adds `SFGAO_CANRENAME` to the attribute mask `SHELL32_GetItemAttributes()`
  allows for drive items. Windows reports it for drives (renaming a drive
  relabels the volume) and ReactOS' `CDrivesFolder` does too; Wine omits it,
  so `IShellFolder::GetAttributesOf(SFGAO_CANRENAME)` returns 0 for every
  drive. VirtualDJ uses exactly that attribute to tell real drives apart
  from shell namespace extensions when it fills `Local Music → Drives`, so
  under stock Wine it discards every drive and the folder renders empty.
  General-purpose, not VirtualDJ-specific. Harmless side effect: drives now
  advertise themselves as renameable, but `ISF_MyComputer_fnSetNameOf()` is
  a stub returning `E_FAIL`, so an actual rename just fails. Not filed
  upstream yet.

- `0003-wined3d-fix-vk-swapchain-rendering-too-dark-by-suppo.patch` —
  `dlls/wined3d/swapchain.c`, `dlls/wined3d/view.c`. Carried unmodified from
  wine-staging's `wined3d_unorm_srgb` series: supports render target views
  for swapchains with more than one back buffer, without which Vulkan
  swapchain output renders too dark and VirtualDJ's skin shows UI glitches.
  This build is `.full` rather than `.staging`, so the patch is carried here
  instead of coming in with the Staging set.

- `winex11-pinch-to-wheel.patch` — `dlls/winex11.drv/mouse.c`,
  `dlls/winex11.drv/x11drv.h`. Negotiates XInput 2.4 instead of 2.2, selects
  touchpad pinch gesture events next to the touch events Wine already
  selects on its windows, and turns each 15% of pinch scale into one
  `WM_MOUSEWHEEL` notch at the cursor: spreading the fingers is wheel up,
  pinching wheel down. Stock Wine never asks the X server for pinch events,
  so the BPM editor, which zooms only on the wheel and ignores keyboard
  mappings, cannot be zoomed without a mouse wheel or two-finger scroll.
  Deliberately not Windows-faithful: Windows delivers pinch to legacy apps
  as Ctrl+wheel, but plain wheel is what zooms in VirtualDJ. Needs an X server
  with XI 2.4 gestures (verified with XWayland 24.1 under mutter, which
  forwards `zwp_pointer_gestures_v1` pinches to X11 windows); an older
  server negotiates a lower version and nothing changes. Not upstreamable as is.

- `ntdll-execution-state-idle-inhibit.patch` — `dlls/ntdll/unix/system.c`,
  `dlls/ntdll/Makefile.in`. Turns `NtSetThreadExecutionState` from a stub
  into a logind "idle" inhibitor lock: `ES_CONTINUOUS | ES_DISPLAY_REQUIRED`
  takes it, `ES_CONTINUOUS` alone releases it. VirtualDJ makes exactly that
  pair, once at startup and once at exit (traced with `+relay`), and the
  DDJ-FLX10 talks MIDI/HID rather than through libinput, so without this a
  set played from the controller alone lets the screen dim, blank and lock.
  logind returns the lock as a file descriptor, so a crash or kill releases
  it too. libdbus is `dlopen`ed the way `mountmgr.sys` does it, on a private
  connection closed right after the call. Honoured by KDE's PowerDevil
  (no dimming, blanking, auto-lock or idle suspend while held); GNOME does
  not watch logind idle inhibitors as far as known (untested). Deliberate
  simplifications: one state per process rather than per thread,
  `ES_SYSTEM_REQUIRED` alone takes no lock (logind's nearest match would
  also refuse user-initiated suspend), and one-shot calls without
  `ES_CONTINUOUS` are not forwarded. Not filed upstream yet.

- `kernelbase-isenclavetypesupported.patch` — `dlls/kernelbase/memory.c`,
  `dlls/kernelbase/kernelbase.spec`, `dlls/kernel32/kernel32.spec`,
  `include/winbase.h`. Exports `IsEnclaveTypeSupported` from kernelbase (and
  kernel32, forwarding to it), always answering FALSE with
  `ERROR_NOT_SUPPORTED`, which is what Windows says on a machine without VBS
  and the true answer under Wine. Wine lists the function only as a
  commented-out stub, so it is missing from the exports entirely, and the
  loader binds the import to a thunk that raises `EXCEPTION_WINE_STUB`
  (0x80000100) when called. VirtualDJ 8.5.9729 calls
  `IsEnclaveTypeSupported(ENCLAVE_TYPE_VBS)` on every start, to fill a
  `vbs=yes|no` tag in the settings summary it builds next to `eqMode=`,
  `stemsMode=` and `stemsFix=`, so without this it crashes within seconds of
  launch, and its crash guard relaunches it in a loop. Still a stub in Wine
  11.21. Not filed upstream yet.

## Built per module

These are not in the `patches` list. Each set is built into its one module
(`winewayland.so`, `dxgi.dll`, `d3d11.dll`), which is then swapped into the full build, so
changing one does not rebuild all of Wine.

The `virtualdj` command runs on the Wayland driver, and these patches are
what make it usable for VirtualDJ on KDE Plasma. What was
tested, what is still open and what Wayland rules out is in
`WAYLAND-GAPS.md`. None is filed upstream.

- `winewayland-smooth-scroll.patch` — `wayland_pointer.c`. Turns touchpad
  scroll distance (`wl_pointer.axis` with no notch attached) into wheel
  messages, in whole notches with the remainder carried over, as XWayland
  does. Stock Wine ignores it, so two-finger scroll does nothing.

- `winewayland-app-move.patch` — `window.c`, `wayland_pointer.c`,
  `waylanddrv.h`. When an application moves its own window with
  `SetWindowPos` while a button is down (a skin title bar), hands the move to
  the compositor with `xdg_toplevel_move`. Without it the surface stays put
  while the Win32 position changes, the pointer appears to move by the same
  amount, and the window runs away until clicks no longer reach it.

- `winewayland-fractional-size.patch` — `wayland_surface.c`, `window.c`.
  Maps the window size to surface coordinates from the origin, so that at a
  fractional scale it no longer depends on the window position and comes out
  a pixel off the client surface (a white line along one edge).

- `winewayland-placed-popups.patch` — `window.c`. Makes a bare, unowned
  popup (menu, dropdown) a subsurface of the window under it, so it appears
  where the application put it, not where the compositor places new windows.

- `winewayland-pinch-to-wheel.patch` — `wayland.c`, `wayland_pointer.c`,
  `waylanddrv.h`, `Makefile.in`, vendored
  `pointer-gestures-unstable-v1.xml`. The Wayland twin of
  `winex11-pinch-to-wheel.patch`: binds `zwp_pointer_gestures_v1` and turns
  pinch scale into `WM_MOUSEWHEEL` notches.

- `winewayland-swap-frame-timeout.patch` — `opengl.c`. A buffer swap waits
  at most 100 ms for the compositor's frame callback, and once the
  compositor has stopped sending them (hidden or unmapped surface) does not
  wait at all until they return. Stock Wine waits without limit, and since
  one wined3d thread draws every window of the process, one hidden window
  that keeps drawing stops all of them.

- `winewayland-subsurface-pointer.patch` — `wayland_surface.c`, `window.c`,
  `wayland_pointer.c`, `waylanddrv.h`. Sends a subsurface's new position as
  soon as the window moves, not with its next drawn frame, and maps pointer
  positions with the position the compositor has confirmed. Without it,
  owned windows (VirtualDJ's editors) do not follow a drag and clicks land
  in the wrong place.

- `winewayland-subsurface-stacking.patch` — `window.c`, `wayland_surface.c`,
  `wayland_pointer.c`, `waylanddrv.h`. Stacks the subsurfaces of one owner
  in Win32 z-order: when a window is shown or its z-order changes, its
  surface is placed right above the next window down that shares its owner,
  and a plain move leaves the order alone. A button press on a subsurface
  raises its window, which the compositor only does for toplevels. Stock
  Wine places every subsurface "above the owner", which is below all the
  others, so a menu opened from an owned window appears underneath it.

- `winewayland-grab-pointer.patch` — `wayland_pointer.c`. Stops clamping the
  pointer position to the window while a button is held. Stock Wine always
  clamps, so in a drag that leaves the window (resizing an editor by its
  edge) the application sees the pointer one pixel inside the edge and the
  window grows a pixel or two per motion event, however far the pointer
  went.

- `winewayland-work-area-maximize.patch` — `wayland.c`, `wayland_surface.c`,
  `display.c`, `window.c`, `waylanddrv.h`. Binds `xdg_wm_base` version 4
  and reports the size from `xdg_toplevel.configure_bounds` as the
  monitor's work area, where stock Wine reports the whole monitor. A window
  sized to exactly the work area is then maximized with
  `xdg_toplevel_set_maximized`, with the lifted size limits committed
  first: KWin will neither maximize nor restore a window it still takes for
  fixed-size. VirtualDJ
  has no `WS_MAXIMIZE`: its maximized state is a window on the work area,
  which stock Wine cannot tell from full screen. Wayland does not say where
  a panel is, so the work area is taken from the monitor's top left.
  The maximized state is remembered rather than re-derived when the
  compositor resizes the window, and a window with no maximize box that the
  compositor maximizes gets that state instead of `WS_MAXIMIZE`.

- `winewayland-monitor-position.patch` — `display.c`. Puts each monitor's
  position into its mode list. With one mode per output, as KWin reports,
  win32u takes the position from that list, where stock Wine leaves it at
  0,0: a second screen then lies on top of the first, and its usable area
  comes out as the strip the two do not share.

- `winewayland-follow-output.patch` — `wayland_surface.c`, `window.c`,
  `display.c`, `waylanddrv.h`. Listens to `wl_surface.enter/leave` and
  moves a toplevel's Win32 position to the monitor of the output it is
  really on, so an application asking which monitor its window is on gets
  the true answer. Full screen is requested on the output the window
  covers (`xdg_toplevel_set_fullscreen` with an output, where stock Wine
  passes none), and whether a window is full screen is taken from the
  compositor, not from a position that is not real.

- `winewayland-popup-toplevel.patch` — `window.c`. Attaches a popup to the
  toplevel it opens over when that is not its owner: the one the pointer is
  in, or else the one that holds its top left corner. VirtualDJ's menus are
  all owned by the main window, so a menu opened from the Visuals window on
  another screen was placed from the main window's surface, at its scale,
  and underneath the Visuals window.

- `winewayland-scale-lock-order.patch` — `wayland_surface.c`. The scale
  handler lets go of the window data before it has win32u update the client
  surfaces. Stock Wine holds it, while a thread that updates client
  surfaces from win32u takes the two locks the other way round; a window
  appearing on a screen of another scale froze the program.

- `winewayland-fullscreen-retarget.patch` — `window.c`, `waylanddrv.h`.
  Asks for full screen again when a window that is full screen is moved to
  another monitor, leaving full screen first: KWin keeps a full-screen
  window on its output otherwise. Also holds back the move of a window's
  Win32 position to its output while full screen is asked for and not yet
  granted.

- `winewayland-touch.patch` — new `wayland_touch.c`, `wayland.c`,
  `waylanddrv.h`, `Makefile.in`. `wl_touch` input sent on as
  `WM_POINTERDOWN/UPDATE/UP`, as winex11 does. **Not in the build:** it
  compiles but has never been run, for lack of a touchscreen.

- `dxgi-output-waitforvblank.patch` — `dlls/dxgi/output.c`. Implements
  `IDXGIOutput::WaitForVBlank`, a stub returning `E_NOTIMPL` in Wine 11.21,
  by sleeping until the next multiple of the refresh period. VirtualDJ's
  frame limiter is built on it: it waits refresh rate / `skinFPS` vertical
  blanks before each frame and ignores the return value. With the stub the
  limiter did nothing, the skin ran at about 115 fps, and with the Visuals
  window and Visualization Settings open the GUI stalled for 100 ms at a
  time. Applies under X11 and Wayland alike. The vertical blank is
  approximated from the clock, not taken from the display.

- `d3d11-texture2d-initial-data-fault.patch` — `dlls/d3d11/texture.c`.
  Catches a page fault while `CreateTexture2D` copies its initial data, lets
  go of the wined3d lock and returns `E_INVALIDARG`. VirtualDJ sometimes
  hands over less memory than the texture needs and catches the fault
  itself; on Windows nothing is locked there, in Wine the global wined3d
  lock stayed held and every thread using Direct3D stopped, the render
  thread and then the whole program. Seen once a second window (Visuals on
  the TV) is open and the frame limiter works. The half-made texture is
  leaked. Other calls that copy application memory under that lock are not
  guarded.

Delete a patch from `flake.nix`'s `patches` list once its fix lands in
upstream Wine and the pinned `wine-src` moves past it.
