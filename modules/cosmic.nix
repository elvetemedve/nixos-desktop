{ config, lib, ... }:

# COSMIC as a third session in the login manager, alongside GNOME and Plasma
# (plasma.nix).
# Trial for eGPU hotplug: cosmic-comp (Smithay) picks up and drops DRM devices
# at runtime.
{
  services.desktopManager.cosmic.enable = true;

  # COSMIC turns this on by default; it retunes CPU scheduling system-wide,
  # which would also affect the GNOME/Plasma sessions and VirtualDJ audio.
  services.system76-scheduler.enable = lib.mkForce false;

  # COSMIC Greeter (on greetd) is the login manager for all three sessions,
  # instead of GDM: gnome-shell 51 only offers fingerprint on its lock screen,
  # not at login (gnome-shell#9478).
  services.displayManager.cosmic-greeter.enable = true;

  # Fingerprint first: greetd relays PAM messages one by one and the greeter
  # shows pam_fprintd's "place your finger" prompt. The password field appears
  # once fprintd gives up (30s or 3 failed scans); a failed password restarts
  # the conversation and re-arms the reader. The greeter ignores Enter on an
  # empty password field, so a password-first stack couldn't fall back to the
  # reader. Fingerprint logins don't unlock KWallet.
  security.pam.services.greetd.rules.auth.fprintd = lib.mkIf config.services.fprintd.enable {
    order = config.security.pam.services.greetd.rules.auth.login.order - 10;
    control = "sufficient";
    modulePath = "${config.services.fprintd.package}/lib/security/pam_fprintd.so";
  };

  # greetd substacks "login", which also gets pam_fprintd by default; keep it
  # out so TTY logins stay password-only (as under GDM) and the greeter doesn't
  # wait on the reader a second time after the rule above gives up.
  security.pam.services.login.fprintAuth = false;
}
