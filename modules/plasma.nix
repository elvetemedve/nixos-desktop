{ config, lib, pkgs, ... }:

# KDE Plasma 6 as a second session next to GNOME, picked from GDM's gear menu.
# Trial for eGPU hotplug: KWin handles GPUs appearing/disappearing at runtime,
# unlike mutter (see blackwell-egpu-manager.nix).
{
  services.desktopManager.plasma6.enable = true;

  # Both GNOME (seahorse) and Plasma (ksshaskpass) set an askpass helper.
  programs.ssh.askPassword = lib.mkForce "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";

  # kscreenlocker runs kde-fingerprint as a second PAM conversation next to the
  # password one ("kde") and never shows its prompts. NixOS's default stack falls
  # back to pam_unix once pam_fprintd gives up (30s timeout, too many tries,
  # verify aborted by suspend), which then waits in a hidden password prompt:
  # the reader stays dead until a wrong password resets the greeter.
  security.pam.services.kde-fingerprint = lib.mkIf config.services.fprintd.enable {
    unixAuth = false;
    # Keep the reader armed for as long as the lock screen is up.
    rules.auth.fprintd.settings.timeout = -1;
  };

  # The greeter cancels the password prompt on suspend and resume so that all
  # authenticators restart, but "kde" asks for the password up to three times
  # (unix-early, kwallet, unix), so one cancel never ends the conversation and a
  # fingerprint scan aborted by the suspend is never restarted. Fail on the
  # first cancelled prompt instead (pam_unix reports it as PAM_AUTHTOK_ERR);
  # wrong passwords behave as before.
  security.pam.services.kde.rules.auth.unix-early.control =
    lib.mkForce "[success=ok new_authtok_reqd=ok authtok_err=die default=ignore]";
}
