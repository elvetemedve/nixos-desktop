{ pkgs, ... }:
{
  # Configure Gnome Console settings
  dconf.settings = {
    "org/gnome/Console" = {
      audible-bell = false;
      custom-font = "MesloLGS Nerd Font Mono 13";
      transparency = true;
    };
  };
  home.packages = with pkgs; [
    gnome-console # Install the Gnome Console (simple terminal emulator)
  ];
}

