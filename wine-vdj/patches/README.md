# Patches

Four local patches plus one carried from wine-staging. All apply cleanly with
`patch -p1` against the pinned `wine-src` (currently Wine 11.16).

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

Delete a patch from `flake.nix`'s `patches` list once its fix lands in
upstream Wine and the pinned `wine-src` moves past it.
