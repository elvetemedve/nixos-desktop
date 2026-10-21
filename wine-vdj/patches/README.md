# Patches

Six local patches plus one carried from wine-staging. All apply cleanly with
`patch -p1` against the pinned `wine-src` (currently Wine 11.20).

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

Delete a patch from `flake.nix`'s `patches` list once its fix lands in
upstream Wine and the pinned `wine-src` moves past it.
