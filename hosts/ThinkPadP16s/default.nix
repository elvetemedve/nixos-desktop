{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/egpu.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/security.nix
    ../../modules/system.nix
    ../../modules/plasma.nix
    ../../modules/cosmic.nix

    ../../modules/ddj-flx10.nix
    ../../modules/external-ssd.nix
    ../../modules/qlcplus
    ../../modules/virtualdj

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadP16s"; # Define your hostname.
}

