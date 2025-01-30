{ pkgs, ... }:
{
  home.packages = with pkgs; [
    keepassxc # KeePassXC offline password manager
  ];
}

