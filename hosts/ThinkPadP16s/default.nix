{ config, pkgs, ... }:
{
  imports = [
    ../../modules/webserver.nix
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];
}

