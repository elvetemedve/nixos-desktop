{ config, pkgs, ... }:
{
  imports = [
    ../../modules/browser.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];
}

