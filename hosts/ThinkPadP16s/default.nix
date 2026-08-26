{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/security.nix
    ../../modules/system.nix

    ../../modules/ddj-flx10.nix

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadP16s"; # Define your hostname.

  # nouveau fails to init the eGPU's GSP firmware and can wedge suspend/resume
  # (s2idle) if the eGPU is unplugged while the laptop is asleep.
  boot.blacklistedKernelModules = [ "nouveau" ];

  services.udev.extraRules = ''
    # AlphaTheta / Pioneer DJ controllers: let the seated user open the HID node
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2b73", GROUP="users", MODE="0660", TAG+="uaccess"
  '';
}

