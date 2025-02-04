{ ... }:
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark"; # Change Gnome Shell theme to dark
    };

    # Clipboard manager
    "org/gnome/GPaste" = {
      "images-support" = true; # Clipboard can accept images
      "track-extension-state" = true; # Sync daemon state with the extension
    };

    # Gnome window manager
    "org/gnome/mutter" = {
      "edge-tiling" = true;
      "workspaces-only-on-primary" = true; # Switching workspace on primary monitor does not switch windows on secondary monitor
    };

    # Gnome Shell
    "org/gnome/shell" = {
      "disable-user-extensions" = false;
    
      "enabled-extensions" = [
        "places-menu@gnome-shell-extensions.gcampax.github.com" # Shop "Places" menu in top bar
        "windowsNavigator@gnome-shell-extensions.gcampax.github.com" # Select windows in overview mode by Alt+number
        "GPaste@gnome-shell-extensions.gnome.org" # Clipboard integration
      ];
    };
  };
}
