"""Unlock, mount, unmount and report on the VeraCrypt volume on the USB SSD.

This is a thin client. udisksd, contacted over the system D-Bus, does the
device-mapper and mount work; polkit lets us ask for it without sudo. See
external-ssd.nix for how that authorisation is arranged, and for how the drive
gets recognised as a VeraCrypt volume in the first place.

Commands:
  mount   unlock the volume if locked, then mount it
  umount  unmount the volume and lock it
  status  report whether it is attached / unlocked / mounted

Only `mount` needs the passphrase, and it is read exactly once: from the
systemd credential at $CREDENTIALS_DIRECTORY/<CRED_NAME> that
external-ssd.service is started with. Run `mount` from a shell -- no such
credential in the environment -- and it simply starts that unit and mirrors
its exit status. `umount` and `status` touch no secret and act directly, so
they work from anywhere, as the user.

Quirks this works around:
  * After an unclean unplug udisksd holds on to stale mount state, so Mount
    can answer AlreadyMounted and Unmount NotMounted; both just mean the
    volume is already in the state we asked for.
  * Deriving a VeraCrypt header key is deliberately slow and cryptsetup tries
    every PRF before rejecting a wrong passphrase, so the D-Bus call timeouts
    are set well above dbus-python's 25 s default.
  * udisksd needs a moment after Unlock to probe the new device and export a
    Filesystem interface, so mount polls for it briefly.

The @NAME@ tokens are substituted by external-ssd.nix at build time.
"""

import argparse
import os
import subprocess
import sys
import time

import dbus

DEVICE = "@device@"
CRED_NAME = "@credName@"
MOUNT_UNIT = "@mountUnit@"
SYSTEMCTL = "@systemctl@"  # noqa: E501 -- a store path once substituted
JOURNALCTL = "@journalctl@"  # noqa: E501 -- a store path once substituted

BUS_NAME = "org.freedesktop.UDisks2"
MANAGER_PATH = "/org/freedesktop/UDisks2/Manager"
IFACE_MANAGER = "org.freedesktop.UDisks2.Manager"
IFACE_ENCRYPTED = "org.freedesktop.UDisks2.Encrypted"
IFACE_FILESYSTEM = "org.freedesktop.UDisks2.Filesystem"
IFACE_PROPS = "org.freedesktop.DBus.Properties"

# Stale-state replies from udisksd; both mean "already as requested".
ERROR_ALREADY_MOUNTED = "org.freedesktop.UDisks2.Error.AlreadyMounted"
ERROR_NOT_MOUNTED = "org.freedesktop.UDisks2.Error.NotMounted"

# D-Bus call timeouts, in seconds; unlock is slow, see the module docstring.
UNLOCK_TIMEOUT = 600
MOUNT_TIMEOUT = 120

# Seconds to wait for the Filesystem interface to appear after Unlock.
PROBE_TIMEOUT = 15


def fail(message):
    print("external-ssd: " + message, file=sys.stderr)
    raise SystemExit(1)


def interface(bus, path, name):
    return dbus.Interface(bus.get_object(BUS_NAME, path), name)


def get_property(bus, path, iface, name):
    props = interface(bus, path, IFACE_PROPS)
    return props.Get(iface, name)


def resolve_block(bus):
    """Object path of the encrypted drive, or None if it is not attached."""
    manager = interface(bus, MANAGER_PATH, IFACE_MANAGER)
    spec = dbus.Dictionary({"path": dbus.String(DEVICE)}, signature="sv")
    paths = manager.ResolveDevice(spec, dbus.Dictionary({}, signature="sv"))
    return str(paths[0]) if paths else None


def cleartext_of(bus, block):
    """Object path of the unlocked device behind a block, or None if locked."""
    try:
        path = get_property(bus, block, IFACE_ENCRYPTED, "CleartextDevice")
    except dbus.DBusException:
        fail(
            DEVICE + " is not offered as an encrypted device by udisks2. "
            "VeraCrypt detection needs /etc/udisks2/tcrypt.conf to exist "
            "and udisksd to have been restarted since it appeared."
        )
    return None if str(path) == "/" else str(path)


def mount_points(bus, path):
    """Mount points of a filesystem, [] if unmounted, None if not one."""
    try:
        raw = get_property(bus, path, IFACE_FILESYSTEM, "MountPoints")
    except dbus.DBusException:
        return None
    # udisks hands out paths as NUL-terminated byte arrays.
    return [bytes(p).rstrip(b"\0").decode() for p in raw]


def await_filesystem(bus, path):
    """Wait for PATH to expose a filesystem; fail after PROBE_TIMEOUT."""
    deadline = time.monotonic() + PROBE_TIMEOUT
    while True:
        points = mount_points(bus, path)
        if points is not None:
            return points
        if time.monotonic() > deadline:
            fail(
                "unlocked " + path + " but it holds no mountable filesystem "
                "(a partitioned VeraCrypt volume would need its partition "
                "mounted instead)"
            )
        time.sleep(0.25)


def passphrase():
    """Read the passphrase from this unit's systemd credential."""
    with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"],
                           CRED_NAME), "rb") as handle:
        secret = handle.read()
    if not secret:
        fail("the passphrase credential is empty -- is /etc/external-ssd.key "
             "set, with no trailing newline?")
    return secret.decode()


def start_mount_unit():
    """Start MOUNT_UNIT (the only context with the passphrase) and exit."""
    # `start` on a Type=oneshot blocks until ExecStart finishes.
    started = subprocess.run([SYSTEMCTL, "start", MOUNT_UNIT])
    if started.returncode != 0:
        subprocess.run([JOURNALCTL, "--no-pager", "-b", "-n", "15",
                        "-u", MOUNT_UNIT])
    raise SystemExit(started.returncode)


def cmd_mount(bus, block):
    clear = cleartext_of(bus, block)
    if clear is None:
        encrypted = interface(bus, block, IFACE_ENCRYPTED)
        options = dbus.Dictionary({}, signature="sv")
        clear = str(
            encrypted.Unlock(passphrase(), options, timeout=UNLOCK_TIMEOUT)
        )
        print("unlocked " + DEVICE + " as " + clear)
    points = await_filesystem(bus, clear)
    if points:
        print("already mounted on " + points[0])
        return
    filesystem = interface(bus, clear, IFACE_FILESYSTEM)
    options = dbus.Dictionary({}, signature="sv")
    try:
        where = str(filesystem.Mount(options, timeout=MOUNT_TIMEOUT))
    except dbus.DBusException as error:
        if error.get_dbus_name() != ERROR_ALREADY_MOUNTED:
            raise
        points = mount_points(bus, clear) or []
        print("already mounted" + (" on " + points[0] if points else ""))
        return
    print("mounted on " + where)


def cmd_umount(bus, block):
    clear = cleartext_of(bus, block)
    if clear is None:
        print(DEVICE + " is already locked")
        return
    options = dbus.Dictionary({}, signature="sv")
    if mount_points(bus, clear):
        try:
            interface(bus, clear, IFACE_FILESYSTEM).Unmount(options)
        except dbus.DBusException as error:
            if error.get_dbus_name() != ERROR_NOT_MOUNTED:
                raise
    interface(bus, block, IFACE_ENCRYPTED).Lock(options)
    print("unmounted and locked " + DEVICE)


def cmd_status(bus, block):
    clear = cleartext_of(bus, block)
    if clear is None:
        print("attached, locked")
        return
    points = mount_points(bus, clear) or []
    if points:
        print("attached, unlocked as " + clear + ", mounted on " + points[0])
    else:
        print("attached, unlocked as " + clear + ", not mounted")


COMMANDS = {"mount": cmd_mount, "umount": cmd_umount, "status": cmd_status}


def main():
    parser = argparse.ArgumentParser(
        prog="external-ssd",
        description="Unlock and mount " + DEVICE + " without root.",
    )
    parser.add_argument("command", choices=sorted(COMMANDS))
    args = parser.parse_args()

    # `mount` from a shell has no credential; hand off to the unit instead.
    if args.command == "mount" and "CREDENTIALS_DIRECTORY" not in os.environ:
        start_mount_unit()

    bus = dbus.SystemBus()
    block = resolve_block(bus)
    if block is None:
        # No drive: umount and status are already satisfied, only mount is not.
        if args.command == "mount":
            fail(DEVICE + " is not attached")
        print("not attached")
        return
    COMMANDS[args.command](bus, block)


if __name__ == "__main__":
    main()
