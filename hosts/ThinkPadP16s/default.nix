{ config, pkgs, ... }:
{
  imports = [
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];
}

