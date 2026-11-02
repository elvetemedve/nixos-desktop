{ config, pkgs, username, ... }:
{
  # Built-in touchpad (the shared list lives in home/plasma.nix)
  home-manager.users.${username}.programs.plasma.input.touchpads = [
    {
      name = "GXTP5100:00 27C6:01EA Touchpad";
      vendorId = "27c6";
      productId = "01ea";
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

  networking.hostName = "ThinkPadX9-15"; # Define your hostname.
}

