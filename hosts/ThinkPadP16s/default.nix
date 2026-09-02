{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/egpu.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/security.nix
    ../../modules/system.nix

    ../../modules/ddj-flx10.nix
    ../../modules/external-ssd.nix
    ../../modules/virtualdj.nix

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadP16s"; # Define your hostname.
}

