# Mounts the VeraCrypt-encrypted USB SSD without root, and without the
# passphrase ever sitting on this machine's unencrypted root filesystem.
#
# Plugging the drive in is the whole interaction: a udev rule starts
# external-ssd.service in the *user's* systemd manager, which reads the
# passphrase out of the running KeePassXC and hands it to udisks2 over D-Bus.
# `external-ssd mount|umount|status` does the same thing by hand.
#
# Why none of this needs sudo, a setuid binary or an /etc/crypttab entry:
#
#   * udisks2 can open VeraCrypt (TCRYPT) volumes itself, but only when
#     /etc/udisks2/tcrypt.conf exists. udisksd tests for that file once at
#     startup and never reads it (src/main.c), so an empty file is the whole
#     switch. With it on, every block device libblkid cannot identify gets a
#     chi-square test for randomness, and the ones that look like ciphertext
#     get an org.freedesktop.UDisks2.Encrypted interface. This drive is a
#     whole-disk volume -- no partition table, no filesystem signature -- so
#     that probe is the only reason it is recognisable as encrypted at all,
#     in GNOME Files and Disks as much as here.
#
#   * The polkit actions udisksd then checks, encrypted-unlock and
#     filesystem-mount, are allow_active=yes by default. They are the ones
#     that apply because the drive's HintSystem is false (USB, hot-pluggable),
#     and "active" holds for a systemd user unit too: polkit falls back to the
#     user's display session when the calling process has no session of its
#     own. So the daemon does the privileged work and we are simply allowed to
#     ask for it, with no authentication prompt.
#
#   * KeePassXC already serves the Secret Service API (FdoSecrets, see
#     home/secret.nix), which is what makes fetching the passphrase possible
#     without storing a copy of it anywhere.
#
# The one part that cannot be declared here: the KeePassXC entry needs the
# custom attribute named below, and has to live in a group that is exposed
# under Settings -> Secret Service Integration.
{ pkgs, username, ... }:

let
  # The SSD's own serial, not the enclosure's -- ID_USB_SERIAL_SHORT is a
  # generic 012345678952 that any other case of this make would also report.
  serial = "CT2000P310SSD8_25375323F879";
  device = "/dev/disk/by-id/ata-${serial}";

  # Attribute pair identifying the KeePassXC entry holding the passphrase.
  # An attribute rather than the title, so renaming the entry cannot break
  # this and no other entry can match by accident.
  secretAttr = "veracrypt";
  secretValue = "usb-2tb";

  external-ssd = pkgs.writers.writePython3Bin "external-ssd"
    {
      libraries = [ pkgs.python3Packages.dbus-python ];
    }
    (builtins.replaceStrings
      [ "@device@" "@secretTool@" "@secretAttr@" "@secretValue@" ]
      [ device "${pkgs.libsecret}/bin/secret-tool" secretAttr secretValue ]
      (builtins.readFile ./external-ssd.py));
in
{
  # libsecret for `secret-tool lookup ${secretAttr} ${secretValue}`, which is
  # the quickest way to check the KeePassXC half in isolation.
  environment.systemPackages = [ external-ssd pkgs.libsecret ];

  # Contents are irrelevant; existence is the flag. services.udisks2.settings
  # merges with its defaults, so udisks2.conf is left alone.
  services.udisks2.settings."tcrypt.conf" = { };

  # udisksd only tests for that file while starting up, and a change under
  # /etc is not by itself a reason for switch-to-configuration to restart a
  # unit, so the first activation needs a `systemctl restart udisks2` (or a
  # reboot) by hand. Tempting to hang a restartTrigger off the unit, but
  # udisks2.service comes from the package rather than from systemd.services:
  # naming it there gets it NixOS's default service environment, whose PATH
  # is coreutils/findutils/gnugrep/gnused/systemd -- replacing the manager's
  # PATH, which is where udisksd finds mkfs, fsck and the mount helpers.

  # services.udev.extraRules is types.lines, so this merges with the rules
  # defined elsewhere rather than replacing them.
  services.udev.extraRules = ''
    # The VeraCrypt USB SSD: unlock and mount it in the user's session on
    # attach. systemd's own rules already tag block devices with "systemd";
    # SYSTEMD_USER_WANTS is what makes the user manager pull the unit in
    # rather than PID 1, which is what keeps this unprivileged.
    ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", \
      ENV{ID_SERIAL}=="${serial}", \
      ENV{SYSTEMD_USER_WANTS}+="external-ssd.service"
  '';

  systemd.user.services.external-ssd = {
    description = "Unlock and mount the VeraCrypt USB volume";

    # Deliberately not wantedBy anything: the udev rule above is the only
    # thing that starts it. That covers logging in with the drive already
    # attached too, since the user manager applies SYSTEMD_USER_WANTS when it
    # enumerates devices at startup -- `external-ssd mount` is idempotent, so a
    # repeated trigger just reports the existing mount point.
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${external-ssd}/bin/external-ssd mount";

      # Long enough to sit through a KeePassXC master password prompt: at
      # login this can start before KeePassXC has autostarted, and the secret
      # lookup then waits for it and unlocks the database on demand.
      TimeoutStartSec = "10min";
    };
  };

  # Unmount and lock before suspending, so a sleeping laptop is never carrying
  # the volume's key in kernel memory. systemd-suspend.service is
  # After=sleep.target, so Before= plus WantedBy= on that target lands this
  # ahead of the actual suspend; if it fails, Wants= is weak enough that the
  # machine still goes to sleep.
  #
  # A system unit, because the user manager has no sleep.target -- but running
  # as the user rather than as root, because udisks2 skips authorisation
  # altogether when the caller is the uid that mounted and unlocked the device
  # (uid 0 is exempt as well, but nothing here needs to reach for that). The
  # session bus is not involved: locking never touches KeePassXC.
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
