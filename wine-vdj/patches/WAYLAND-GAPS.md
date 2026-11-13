# winewayland.drv gaps for VirtualDJ

State on 2026-11-12. Wine 11.21, KDE Plasma (KWin 6.8.2), VirtualDJ
8.5.9729, laptop panel only (120 Hz, scale 1.45, Intel Xe). The reference is
the X11 driver through XWayland on the same session: anything that behaves
differently there counts as a gap.

Tested by hand, one traced run per change (`WINEDEBUG=+waylanddrv` plus
`WAYLAND_DEBUG=1`). Not tested: a second screen or TV, the eGPU, a touchscreen,
sessions longer than a few minutes, any compositor other than KWin.

## Gaps found and patched

"Lines" is the number of added lines in the patch, protocol XML excluded.

| Gap | Symptom in VirtualDJ | Functions added or changed | Lines | Patch | Status |
|-----|----------------------|----------------------------|-------|-------|--------|
| Touchpad scroll dropped | Two-finger scroll did nothing in lists and editors | `pointer_handle_axis`, `pointer_handle_axis_source`, `pointer_handle_axis_stop` (`wayland_pointer.c`) | 63 | `winewayland-smooth-scroll` | Confirmed fixed |
| Windows the application moves by itself | Dragging the main window by its skin title bar ran away and froze input; this was the freeze that ended both earlier attempts | new `is_app_move`, `wayland_win_data_start_move`, `WM_WAYLAND_END_MOVE`; `WAYLAND_WindowPosChanged` (`window.c`); pointer enter (`wayland_pointer.c`) | 124 | `winewayland-app-move` | Confirmed fixed |
| Size rounding at fractional scale | White line along a window edge at scale 1.45 | `wayland_surface_reconfigure` (`wayland_surface.c`), `wayland_configure_window` (`window.c`): map the size from the origin | 11 | `winewayland-fractional-size` | Confirmed fixed |
| Unowned popups cannot be placed | Dropdowns and menus opened wherever KWin put them | new `is_placed_popup`, `get_placed_popup_owner`, `get_subsurface_owner` (`window.c`): make them subsurfaces of the window under them | 70 | `winewayland-placed-popups` | Confirmed fixed |
| No pinch gestures | Pinch did not zoom waveforms or the BPM editor | `registry_handle_global` (`wayland.c`); `wayland_pointer_init/deinit` and new pinch begin/update/end listeners (`wayland_pointer.c`); binds `zwp_pointer_gestures_v1` | 88 | `winewayland-pinch-to-wheel` | Confirmed fixed |
| Swap blocks on a surface the compositor does not draw | Closing the track editor hung the program; a hidden Visuals window froze the whole GUI, because one wined3d thread draws every window | `wayland_drawable_wait_frame`, `wayland_drawable_swap` (`opengl.c`): 100 ms timeout, then no waiting until frame callbacks return | 88 | `winewayland-swap-frame-timeout` | Confirmed fixed; see open point 1 |
| Subsurface position lags the Win32 position | Editor windows (BPM, POI, track) did not follow a drag, clicks landed in the wrong place, the close button was dead until a resize | new `wayland_surface_place_subsurface`, `wayland_surface_sync_subsurface_position` (`wayland_surface.c`); `wayland_win_data_update_wayland_state` (`window.c`); pointer motion (`wayland_pointer.c`) | 94 | `winewayland-subsurface-pointer` | Confirmed fixed |
| No stacking order among subsurfaces | The Visuals window's context menu opened underneath it; clicking a lower editor window did not bring it to the front. Stock Wine only ever places a subsurface "above the owner", which is below every other subsurface | new `get_subsurface_below`, `WM_WAYLAND_RAISE`; `WAYLAND_WindowPosChanged` (`window.c`); new `wayland_surface_get_sibling_below`; `wayland_surface_place_subsurface` (`wayland_surface.c`); `pointer_handle_button` (`wayland_pointer.c`) | 81 | `winewayland-subsurface-stacking` | Confirmed fixed |
| Pointer clamped to the window during a drag | Resizing an editor window by its edge crawled at about 1 px per motion event once the pointer got ahead of the edge (traced: pointer 300 px ahead, every event clamped) | `pointer_handle_motion_internal` (`wayland_pointer.c`): no clamp while a button is held | 12 | `winewayland-grab-pointer` | Confirmed fixed |
| No touchscreen input | None seen: no touchscreen here. The driver has no `wl_touch` code at all | `seat_handle_capabilities` (`wayland.c`); new `wayland_touch.c` sending `WM_POINTERDOWN/UPDATE/UP` as winex11 does | 199 | `winewayland-touch` | Compiles, never run, not in the build |

Total in the build: 631 lines in nine patches. With touch: 830.

## Not a driver gap

- **Tray.** VirtualDJ shows no tray icon under X11 either. Nothing to do.
- **GUI lag with Visualization Settings open.** Same under X11. The cause was
  Wine's `IDXGIOutput::WaitForVBlank` stub, which failed at once, so
  VirtualDJ's frame limiter did not limit anything. Fixed in dxgi by
  `dxgi-output-waitforvblank.patch` (34 lines), confirmed under X11. A side
  effect is that the `skinFPS` setting now takes effect: with `skinFPS` 30 the
  skin draws at 30 fps where it used to run at about 115.

## Open points

1. **Closed: hidden Visuals window on Wayland, with the dxgi fix.** Before
   the dxgi fix a hidden Visuals window was drawn 1,200 to 8,000 times a
   second, as nothing paced it. With it, the log shows a steady 60 surface
   updates a second, shown or hidden, and the GUI stays responsive with
   Visualization Settings open.
2. **No maximized mode.** The middle title-bar control toggles between
   windowed and full screen; under X11 it has a third, maximized state.
   Probable cause, not confirmed: the driver reports no work area, so a
   window of work-area size is taken for full screen.
3. **Closed: resize from an edge was slow.** The pointer clamp above;
   fixed by `winewayland-grab-pointer.patch`.
4. **Full screen on a chosen output.** `xdg_toplevel_set_fullscreen` is
   called with no output (`wayland_surface_update_state_toplevel`,
   `window.c`), so KWin picks the screen. Needed for "skin on the laptop,
   video on the TV". Estimate 60 to 100 lines. Needs the TV to test.
5. **Programmatic activation.** No `pActivateWindow`, `xdg_activation_v1` is
   not bound. Focus did return to the main window after closing Settings, so
   no symptom so far. Estimate 80 to 120 lines if one turns up.
6. **Stems on the eGPU, long sessions.** Not exercised.

## What Wayland itself rules out

No driver patch changes these.

- A top-level window cannot be placed or asked where it is. A *windowed*
  video window cannot be sent to the TV or have its position restored; only
  full screen can name an output.
- No control over stacking of top-level windows (`HWND_TOPMOST`, raise).
- No pointer position or key state while the pointer or focus is outside
  Wine's own windows. MIDI and HID controllers do not go through Wayland and
  are unaffected.
- No reading of other windows' pixels, which VirtualDJ's screen-grab video
  source needs.
- Clipboard works only while a Wine window has focus on KWin: Wine binds
  `zwlr_data_control_manager_v1`, KWin offers `ext_data_control_manager_v1`.
  Out of scope here.

## Risk of missed gaps

Medium.

- Everything in the first table was found by using the program, not by
  reading the source: of the eight gaps predicted from the source, three were
  real (scroll, pinch, touch), one was a different bug than predicted (the
  freeze), and six new ones appeared only in use.
- So the untested areas (points 4 and 6, a second screen at another scale,
  long sessions) should be expected to hold more of the same kind.
- The patches have been run on KWin only. `winewayland-placed-popups` and
  `winewayland-swap-frame-timeout` depend on compositor behaviour (subsurface
  stacking, when frame callbacks stop) and are the likeliest to behave
  differently elsewhere.
