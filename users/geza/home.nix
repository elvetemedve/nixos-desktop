{ pkgs, ... }:

{
  imports = [
    ../../home/base.nix
    ../../home/browser.nix
    ../../home/shell.nix
  ];

  programs.git = {
    enable = true;
    userName = "Géza Búza";
    userEmail = "bghome@gmail.com";
  };
}
