{pkgs, ...}:

{
  environment.systemPackages = with pkgs; [
    veracrypt # Free Open-Source filesystem on-the-fly encryption
  ];
  services.udev.packages = [ pkgs.nitrokey-udev-rules ]; # Add Udev rules to recognize connected NitroKey devices
}
