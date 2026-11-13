# Blinks the power-button LED at 1 Hz while the fingerprint reader is waiting
# for a finger, as a cue to touch it. See fprint-led.py for the mechanism.
#
# Why the LED is driven from here and not by libfprint or the sensor:
#
#   * On the X9-15 the power LED belongs to the EC. thinkpad_acpi exposes it
#     as tpacpi::power, and the "timer" trigger with its default delays maps
#     onto the EC's own hardware blink, so no extra kernel module beyond the
#     trigger, and no acpi_call, is needed.
#
#   * The BIOS turns the same LED green at its pre-boot fingerprint prompt by
#     sending the Synaptics sensor command 0xAC, but the sensor rejects that
#     command (status 0x0404) outside the BIOS's encrypted session, so green
#     is out of reach from Linux. libfprint has no LED handling at all.
#
#   * fprintd already publishes `finger-needed` on the system bus for every
#     client (greetd, sudo, the lock screens, polkit), so one listener covers
#     them all.
#
{ pkgs, ... }:

let
  led = "/sys/class/leds/tpacpi::power";

  fprint-led = pkgs.writers.writePython3Bin "fprint-led"
    {
      libraries = [ pkgs.python3Packages.pygobject3 ];
    }
    (builtins.replaceStrings [ "@led@" ] [ led ]
      (builtins.readFile ./fprint-led.py));
in
{
  systemd.services.fprint-led = {
    description = "Blink the power LED while the fingerprint reader waits";
    wantedBy = [ "multi-user.target" ];
    after = [ "dbus.service" ];

    serviceConfig = {
      # The "timer" trigger is a module; "+" runs this with full privileges
      # despite the capability lockdown below.
      ExecStartPre = "+${pkgs.kmod}/bin/modprobe ledtrig-timer";
      ExecStart = "${fprint-led}/bin/fprint-led";
      Restart = "on-failure";

      # Root only for the uid: the sysfs files are root-owned 0644, which
      # needs no capability to write.
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };
}
