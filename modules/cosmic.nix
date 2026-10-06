{ lib, ... }:

# COSMIC as a third session in GDM, alongside GNOME and Plasma (plasma.nix).
# Trial for eGPU hotplug: cosmic-comp (Smithay) picks up and drops DRM devices
# at runtime.
{
  services.desktopManager.cosmic.enable = true;

  # COSMIC turns this on by default; it retunes CPU scheduling system-wide,
  # which would also affect the GNOME/Plasma sessions and VirtualDJ audio.
  services.system76-scheduler.enable = lib.mkForce false;
}
