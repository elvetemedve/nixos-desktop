"""Unlock and mount the VeraCrypt volume on the USB SSD, as a plain user.

Nothing here is privileged: udisksd does the device-mapper and mount work and
polkit lets us ask for it, so there is no sudo, no setuid binary and no entry
in /etc/crypttab.  See usb-vault.nix for why that authorisation holds.

The passphrase is read from the running KeePassXC over the Secret Service API.
It lives in this process's memory and in the D-Bus message to udisksd, and
nowhere else -- in particular not in argv (which any local process can read
out of /proc) and not on this machine's unencrypted root filesystem.
"""

import argparse
import getpass
import subprocess
import sys
import time

import dbus

DEVICE = "@device@"
SECRET_TOOL = "@secretTool@"  # noqa: E501 -- a store path once substituted
SECRET_ATTR = "@secretAttr@"
SECRET_VALUE = "@secretValue@"

BUS_NAME = "org.freedesktop.UDisks2"
SECRET_SERVICE = "org.freedesktop.secrets"
MANAGER_PATH = "/org/freedesktop/UDisks2/Manager"
IFACE_MANAGER = "org.freedesktop.UDisks2.Manager"
IFACE_ENCRYPTED = "org.freedesktop.UDisks2.Encrypted"
IFACE_FILESYSTEM = "org.freedesktop.UDisks2.Filesystem"
IFACE_PROPS = "org.freedesktop.DBus.Properties"

# udisksd's own bookkeeping can disagree with the MountPoints property it
# publishes: unplugging a mounted volume leaves the daemon still holding a
# mount that the property no longer reports. Both of these mean the state we
# were asked for is already the state we have.
ERROR_ALREADY_MOUNTED = "org.freedesktop.UDisks2.Error.AlreadyMounted"
ERROR_NOT_MOUNTED = "org.freedesktop.UDisks2.Error.NotMounted"

# Deriving a VeraCrypt header key is deliberately slow, and cryptsetup has to
# try each PRF in turn until one produces a valid header, so a wrong-passphrase
# attempt is the slowest of all.  dbus-python's 25 s default would time out
# long before udisksd is done.
UNLOCK_TIMEOUT = 600
MOUNT_TIMEOUT = 120

# How long to wait for udev to probe the freshly unlocked device and for
# udisksd to export a Filesystem interface for it.
PROBE_TIMEOUT = 15

# How long to wait for KeePassXC to claim the Secret Service.  Logging in with
# the drive already attached starts us from the user manager before KeePassXC
# has autostarted, and losing that race would mean failing on a drive we could
# have mounted a second later.
SECRET_SERVICE_TIMEOUT = 60


def fail(message):
    print("usb-vault: " + message, file=sys.stderr)
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


def secret_service_ready(wait):
    """Whether KeePassXC is on the session bus, optionally waiting for it."""
    try:
        bus = dbus.SessionBus()
    except dbus.DBusException:
        return False
    deadline = time.monotonic() + (SECRET_SERVICE_TIMEOUT if wait else 0)
    while True:
        if bus.name_has_owner(SECRET_SERVICE):
            return True
        if time.monotonic() > deadline:
            return False
        time.sleep(0.5)


def passphrase():
    """From KeePassXC if it will give it to us, from the terminal if not."""
    if secret_service_ready(wait=not sys.stdin.isatty()):
        # A locked database is fine: libsecret asks the Secret Service to
        # unlock the item, which is KeePassXC's own master password prompt.
        lookup = subprocess.run(
            [SECRET_TOOL, "lookup", SECRET_ATTR, SECRET_VALUE],
            stdout=subprocess.PIPE,
            check=False,
        )
        # secret-tool writes the secret verbatim, adding a newline only when
        # its stdout is a terminal -- which here it never is.
        if lookup.returncode == 0 and lookup.stdout:
            return lookup.stdout.decode()
    if sys.stdin.isatty():
        return getpass.getpass("VeraCrypt passphrase: ")
    fail(
        "no secret for " + SECRET_ATTR + "=" + SECRET_VALUE + " from "
        "KeePassXC (not running, entry outside a group exposed through "
        "Secret Service Integration, or access denied) and there is no "
        "terminal to ask on"
    )


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
        prog="usb-vault",
        description="Unlock and mount " + DEVICE + " without root.",
    )
    parser.add_argument("command", choices=sorted(COMMANDS))
    args = parser.parse_args()

    bus = dbus.SystemBus()
    block = resolve_block(bus)
    if block is None:
        # An absent drive is already the state umount is asked to reach, and
        # suspending without it plugged in should not leave a failed unit
        # behind. Only mount has nothing to work with.
        if args.command == "mount":
            fail(DEVICE + " is not attached")
        print("not attached")
        return
    COMMANDS[args.command](bus, block)


if __name__ == "__main__":
    main()
