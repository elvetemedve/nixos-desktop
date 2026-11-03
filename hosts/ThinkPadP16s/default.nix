{ config, pkgs, username, ... }:
{
  # Built-in touchpad (the shared list lives in home/plasma.nix)
  home-manager.users.${username}.programs.plasma.input.touchpads = [
    {
      name = "ELAN0683:00 04F3:320B Touchpad";
      vendorId = "04f3";
      productId = "320b";
      naturalScroll = true;
    }
  ];

  imports = [
    ../../modules/browser.nix
    ../../modules/egpu.nix
    ../../modules/gaming.nix
    ../../modules/webserver.nix
    ../../modules/security.nix
    ../../modules/system.nix
    ../../modules/plasma.nix
    ../../modules/cosmic.nix
    ../../modules/whisrs.nix

    ../../modules/ddj-flx10.nix
    ../../modules/external-ssd.nix
    ../../modules/qlcplus
    ../../modules/virtualdj

    ./hardware-configuration.nix
  ];

  networking.hostName = "ThinkPadP16s"; # Define your hostname.
}

