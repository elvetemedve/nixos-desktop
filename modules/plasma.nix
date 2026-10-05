{ lib, pkgs, ... }:

# KDE Plasma 6 as a second session next to GNOME, picked from GDM's gear menu.
# Trial for eGPU hotplug: KWin handles GPUs appearing/disappearing at runtime,
# unlike mutter (see blackwell-egpu-manager.nix).
{
  services.desktopManager.plasma6.enable = true;

  # Both GNOME (seahorse) and Plasma (ksshaskpass) set an askpass helper.
  programs.ssh.askPassword = lib.mkForce "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
}
