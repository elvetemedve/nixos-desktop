"""Blink the power LED while fprintd is waiting for a finger.

fprintd publishes a `finger-needed` boolean on every device object
(net.reactivated.Fprint.Device) and announces changes with
PropertiesChanged. This daemon listens for those signals on the system bus
and drives one LED class device:

  finger-needed true    trigger "timer" with its default delays, which
                        thinkpad_acpi hands to the EC as its own 1 Hz
                        hardware blink
  finger-needed false   trigger "none" and full brightness: the normal,
                        solid power LED

Things that would otherwise leave the LED blinking:
  * fprintd exits when idle and can crash, so losing the bus name's owner
    counts as "no finger needed".
  * The firmware drives the LED itself across suspend (breathing in modern
    standby, solid on resume), so the current state is re-applied after
    resume.
  * Stopping the service restores the solid LED.

The bus name is only watched, never activated: this daemon must not start
fprintd by itself.

The @NAME@ tokens are substituted by fprint-led.nix at build time.
"""

import signal
import sys

import gi

gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix  # noqa: E402

LED = "@led@"

FPRINT_NAME = "net.reactivated.Fprint"
DEVICE_IFACE = "net.reactivated.Fprint.Device"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
LOGIN_NAME = "org.freedesktop.login1"

# Device object path -> its last reported finger-needed value.
needed = {}
blinking = None


def write(attr, value):
    with open(f"{LED}/{attr}", "w") as f:
        f.write(value)


def apply(force=False):
    global blinking
    want = any(needed.values())
    if want == blinking and not force:
        return
    try:
        # Leave the current trigger first: re-selecting "timer" while it is
        # already active would not restart a blink the firmware cancelled.
        write("trigger", "none")
        if want:
            write("trigger", "timer")
        else:
            with open(f"{LED}/max_brightness") as f:
                write("brightness", f.read().strip())
    except OSError as e:
        print(f"cannot drive {LED}: {e}", file=sys.stderr, flush=True)
        return
    blinking = want
    print("blinking" if want else "solid", flush=True)


def on_properties_changed(conn, sender, path, iface, name, params, data):
    _iface, changed, _invalidated = params.unpack()
    if "finger-needed" in changed:
        needed[path] = bool(changed["finger-needed"])
        apply()


def on_fprintd_vanished(conn, name, data=None):
    needed.clear()
    apply()


def on_prepare_for_sleep(conn, sender, path, iface, name, params, data):
    (going_down,) = params.unpack()
    if not going_down:
        apply(force=True)


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    bus.signal_subscribe(
        FPRINT_NAME, PROPS_IFACE, "PropertiesChanged", None, DEVICE_IFACE,
        Gio.DBusSignalFlags.NONE, on_properties_changed, None)
    bus.signal_subscribe(
        LOGIN_NAME, LOGIN_NAME + ".Manager", "PrepareForSleep",
        "/org/freedesktop/login1", None,
        Gio.DBusSignalFlags.NONE, on_prepare_for_sleep, None)
    Gio.bus_watch_name_on_connection(
        bus, FPRINT_NAME, Gio.BusNameWatcherFlags.NONE,
        None, on_fprintd_vanished)

    apply(force=True)

    loop = GLib.MainLoop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()

    needed.clear()
    apply(force=True)


if __name__ == "__main__":
    main()
