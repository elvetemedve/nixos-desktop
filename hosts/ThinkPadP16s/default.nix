{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/security.nix
    ../../modules/system.nix

    ../../modules/ddj-flx10.nix
    ../../modules/usb-vault.nix
    ../../modules/virtualdj.nix

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadP16s"; # Define your hostname.

  # nouveau fails to init the eGPU's GSP firmware and can wedge suspend/resume
  # (s2idle) if the eGPU is unplugged while the laptop is asleep.
  boot.blacklistedKernelModules = [ "nouveau" ];
}

