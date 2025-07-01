{ pkgs, ... }:
{
  home.packages = with pkgs; [
    file # Determine the type of the given file
    htop # An interactive process viewer
  ];
}
