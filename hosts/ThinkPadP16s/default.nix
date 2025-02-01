{ config, pkgs, ... }:
{
  imports = [
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];
}

