{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/gaming.nix
    ../../modules/virtualization.nix
    ../../modules/webserver.nix
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadP16s"; # Define your hostname.
}

