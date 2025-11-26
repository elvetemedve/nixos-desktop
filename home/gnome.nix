{ username, pkgs, lib, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      "clock-show-weekday" = true; # Display current day of the week on the top bar
      "color-scheme" = "prefer-dark"; # Change Gnome Shell theme to dark
    };

    # Calendar settings
    "org/gnome/desktop/calendar" = {
      "show-weekdate" = true; # Display week of year in the calendar widget
    };

    "org/gnome/desktop/session" = {
      "idle-delay" = lib.hm.gvariant.mkUint32 900; # 15 minutes inactivity until screen blanks
    };

    # Customize global hotkeys
    "org/gnome/desktop/wm/keybindings" = {
      "cycle-group" = [ "<Super>Tab" ];
      "switch-applications" = [ "<Alt>Tab" ];
      "switch-group" = [ "<Super>Above_Tab" ]; # Windows+`
      "switch-group-backward" = [ "<Shift><Super>Above_Tab" ]; # Shift+Windows+`
    };

    # Gnome window manager
    "org/gnome/mutter" = {
      "edge-tiling" = true;
      "workspaces-only-on-primary" = true; # Switching workspace on primary monitor does not switch windows on secondary monitor
    };

    "org/gnome/settings-daemon/plugins/power" = {
      "sleep-inactive-ac-timeout" = 7200; # 2 hours inactivity until suspend/hibernate when connected to AC power
    };

    # Gnome Shell
    "org/gnome/shell" = {
      "disable-user-extensions" = false;
    
      "enabled-extensions" = [
        "clipboard-indicator@tudmotu.com" # Clipboard manager
        "places-menu@gnome-shell-extensions.gcampax.github.com" # Shop "Places" menu in top bar
        "windowsNavigator@gnome-shell-extensions.gcampax.github.com" # Select windows in overview mode by Alt+number
        "System_Monitor@bghome.gmail.com" # System monitor integrated into the top bar
      ];
    };

    # Clipboard manager config
    "org/gnome/shell/extensions/clipboard-indicator" = {
      "toggle-menu" = [ "<Control><Alt>h" ]; # Show the clipboard manger panel by pressing Ctrl+Alt+h
    };
  };

  home.packages = with pkgs; [
    libgtop # Library to read running processed. Used by System Monitor extension.
  ];
  home.sessionVariables."GI_TYPELIB_PATH" = "/etc/profiles/per-user/${username}/lib/girepository-1.0"; # Make Gnome libraries discoverable

  # Run GPaste-Daemon as user service
  systemd.user.services = {
    "org.gnome.GPaste" = {
      Unit = {
        Description = "GPaste daemon";
        PartOf = "graphical-session.target";
        After = "graphical-session.target";
      };

      Service = {
        Type = "dbus";
        BusName = "org.gnome.GPaste";
        ExecStart = "${pkgs.gpaste}/libexec/gpaste/gpaste-daemon";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
