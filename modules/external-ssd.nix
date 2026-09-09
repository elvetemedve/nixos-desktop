# Mounts the VeraCrypt-encrypted USB SSD on plug-in, without sudo and without
# the passphrase ever being readable by anything but the one unit that unlocks
# the drive.
#
# The chain, when the disk appears: a udev rule pulls external-ssd-attach.service
# into the *user* manager; that shim runs `systemctl start external-ssd.service`;
# external-ssd.service -- a *system* unit, running as the user -- runs
# `external-ssd mount`, which drives udisksd over the system D-Bus.
# `external-ssd mount|umount|status` reaches the same system unit by hand.
#
# Two units, because udev's SYSTEMD_USER_WANTS can only name a user unit while
# the real work must run in a system unit (see the passphrase, below). Routing
# the trigger through the user manager is also what we want: it fires only once
# someone is logged in, and fires again at login for a drive left attached.
#
# The passphrase lives in /etc/external-ssd.key, mode 0400 root:root -- in the
# clear, kept out of this tree, and safe at rest only because / is on an Opal
# self-encrypting drive. Nothing unprivileged can read it: not another user, and
# not another process of this user. external-ssd.service is a system unit so
# PID 1 can read it as root; LoadCredential= drops a copy in the unit's
# $CREDENTIALS_DIRECTORY and PrivateMounts= keeps that tmpfs in the unit's own
# mount namespace, so even this user's other processes cannot see the cleartext
# while the oneshot runs. A user-manager unit could not manage this: it runs as
# the user, so it could neither read a root-only file nor hold a secret the
# user's other processes could not also read.
#
# Why none of it needs sudo or an auth prompt:
#
#   * udisksd does the privileged device-mapper and mount work; we only ask.
#
#   * udisksd opens VeraCrypt (TCRYPT) volumes itself, but only when
#     /etc/udisks2/tcrypt.conf exists. It tests for that file once at startup
#     and never reads it (src/main.c), so an empty file is the whole switch.
#     This drive is a whole-disk volume with no partition table or filesystem
#     signature, so udisksd's randomness probe is the only reason it registers
#     as encrypted at all -- here and in GNOME Disks alike.
#
#   * A logged-in user may run encrypted-unlock and filesystem-mount (both
#     allow_active=yes), but external-ssd.service has no login session of its
#     own and polkit will not lend it the user's: a system unit's slice is
#     root-owned, so the uid fallback that covers a user-manager unit does not
#     apply. The polkit rule below therefore grants the user those two actions
#     outright, alongside permission to start the unit.
#
# Caveats:
#
#   * udisksd only checks for tcrypt.conf at startup, and switch-to-configuration
#     will not restart it for a new /etc file, so the first activation needs a
#     manual `systemctl restart udisks2` (or a reboot). A restartTrigger would
#     mean naming udisks2.service under systemd.services, which replaces the
#     manager's PATH -- where udisksd finds mkfs, fsck and the mount helpers.
#
#   * external-ssd-lock unmounts and locks before sleep.target, so a suspended
#     laptop never holds the volume key in kernel memory. It is a system unit
#     (the user manager has no sleep.target) that runs as the user, since
#     udisksd waives authorisation for the uid that mounted the volume.
#
#   * GNOME's automounter would otherwise race us to the unlock and pop its
#     own TCRYPT passphrase dialog, so the udev rule sets UDISKS_AUTO=0 on the
#     disk -- udisks2 still manages it, GNOME just stops auto-acting on it.
#
# Bootstrap, once per machine, as root -- the file must have no trailing
# newline (secret-tool and install both give that):
#
#   secret-tool lookup veracrypt usb-2tb \
#     | sudo install -m 0400 -o root -g root /dev/stdin /etc/external-ssd.key
#
{ config, pkgs, username, ... }:

let
  # The SSD's own serial; the enclosure's is generic to the product line.
  serial = "CT2000P310SSD8_25375323F879";
  device = "/dev/disk/by-id/ata-${serial}";

  # Root-only passphrase file, and the credential name it is exposed under.
  secretFile = "/etc/external-ssd.key";
  credName = "veracrypt-passphrase";

  # The system unit that holds the credential and does the unlock + mount.
  mountUnit = "external-ssd.service";

  # Bake the config into the script; it carries none of its own.
  external-ssd = pkgs.writers.writePython3Bin "external-ssd"
    {
      libraries = [ pkgs.python3Packages.dbus-python ];
    }
    (builtins.replaceStrings
      [ "@device@" "@credName@" "@mountUnit@" "@systemctl@" "@journalctl@" ]
      [
        device
        credName
        mountUnit
        "${pkgs.systemd}/bin/systemctl"
        "${pkgs.systemd}/bin/journalctl"
      ]
      (builtins.readFile ./external-ssd.py));
in
{
  environment.systemPackages = [ external-ssd ];

  # Existence is the switch; contents merge with the udisks2 defaults.
  services.udisks2.settings."tcrypt.conf" = { };

  # Let the user start the mount unit, and let the (session-less) unit unlock
  # and mount -- the two udisks2 actions a logged-in user already has via
  # allow_active. All ${username}-only.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.user != "${username}") { return; }
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "${mountUnit}") {
        return polkit.Result.YES;
      }
      if (action.id == "org.freedesktop.udisks2.encrypted-unlock" ||
          action.id == "org.freedesktop.udisks2.filesystem-mount") {
        return polkit.Result.YES;
      }
    });
  '';

  # On attach: mark the disk UDISKS_AUTO=0 so GNOME's automounter leaves the
  # locked volume alone (the unlock prompt is our job, not its), and pull the
  # shim into the user manager. types.lines, so this merges with other rules.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", \
      ENV{ID_SERIAL}=="${serial}", \
      ENV{UDISKS_AUTO}="0", \
      ENV{SYSTEMD_USER_WANTS}+="external-ssd-attach.service"
  '';

  # Started only by the udev rule; starts the worker (--no-block: slow unlock).
  systemd.user.services.external-ssd-attach = {
    description = "Start the VeraCrypt USB mount on attach or login";
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.systemd}/bin/systemctl start --no-block ${mountUnit}";
    };
  };

  # System unit for LoadCredential; runs as the user for the mount path.
  systemd.services.external-ssd = {
    description = "Unlock and mount the VeraCrypt USB volume";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${external-ssd}/bin/external-ssd mount";
      LoadCredential = "${credName}:${secretFile}";
      PrivateMounts = true;
      # Above the script's 600 s unlock timeout, so systemd does not kill first.
      TimeoutStartSec = "15min";
    };
  };

  # Unmount and lock before sleep; rationale in the header.
  systemd.services.external-ssd-lock = {
    description = "Lock the VeraCrypt USB volume before sleep";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${external-ssd}/bin/external-ssd umount";
    };
  };
}
