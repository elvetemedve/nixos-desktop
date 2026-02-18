{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/security.nix
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadT580"; # Define your hostname.
}

