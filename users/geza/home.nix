{ pkgs, ... }:

{
  imports = [
    ../../home/base.nix
    ../../home/browser.nix
    ../../home/editor.nix
    ../../home/gnome.nix
    ../../home/messaging.nix
    ../../home/secret.nix
    ../../home/shell.nix
    ../../home/storage.nix
    ../../home/terminal.nix
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
