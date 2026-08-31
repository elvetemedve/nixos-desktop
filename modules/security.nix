{pkgs, ...}:

{
  services.udev.packages = [ pkgs.nitrokey-udev-rules ]; # Add Udev rules to recognize connected NitroKey devices
}
