{ pkgs, ... }:

{
  imports = [
    ../../home/audio.nix
    ../../home/base.nix
    ../../home/browser.nix
    ../../home/document.nix
    ../../home/editor.nix
    ../../home/gnome.nix
    ../../home/messaging.nix
    ../../home/secret.nix
    ../../home/shell.nix
    ../../home/storage.nix
    ../../home/terminal.nix
    ../../home/utility.nix
    ../../home/video.nix
  ];

  programs.git = {
    enable = true;
    extraConfig = {
      safe.directory = "/etc/nixos";
    };
    userName = "Géza Búza";
    userEmail = "bghome@gmail.com";
  };
}
