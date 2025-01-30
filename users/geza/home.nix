{ pkgs, ... }:

{
  imports = [
    ../../home/base.nix
    ../../home/browser.nix
    ../../home/shell.nix
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
