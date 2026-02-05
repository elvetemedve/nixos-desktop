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

  # Set default apps for opening file types
  # see also https://wiki.nixos.org/wiki/Default_applications
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Firefox for browsing the Web
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "application/xhtml+xml" = "firefox.desktop";

      # Gapless for playing Music
      "audio/x-vorbis+ogg" = "com.github.neithern.g4music.desktop";
      "audio/wav" = "com.github.neithern.g4music.desktop";
      "audio/webm" = "com.github.neithern.g4music.desktop";
      "audio/x-aac" = "com.github.neithern.g4music.desktop";
      "audio/x-aiff" = "com.github.neithern.g4music.desktop";
      "audio/x-ape" = "com.github.neithern.g4music.desktop";
      "audio/x-flac" = "com.github.neithern.g4music.desktop";
      "audio/x-it" = "com.github.neithern.g4music.desktop";
      "audio/x-m4a" = "com.github.neithern.g4music.desktop";
      "audio/x-m4b" = "com.github.neithern.g4music.desktop";
      "audio/x-matroska" = "com.github.neithern.g4music.desktop";
      "audio/x-mod" = "com.github.neithern.g4music.desktop";
      "audio/x-mp1" = "com.github.neithern.g4music.desktop";
      "audio/x-mp2" = "com.github.neithern.g4music.desktop";
      "audio/x-mp3" = "com.github.neithern.g4music.desktop";
      "audio/x-mpg" = "com.github.neithern.g4music.desktop";
      "audio/x-mpeg" = "com.github.neithern.g4music.desktop";
      "audio/x-ms-asf" = "com.github.neithern.g4music.desktop";
      "audio/x-ms-asx" = "com.github.neithern.g4music.desktop";
      "audio/x-ms-wax" = "com.github.neithern.g4music.desktop";
      "audio/x-ms-wma" = "com.github.neithern.g4music.desktop";
      "audio/x-musepack" = "com.github.neithern.g4music.desktop";
      "audio/x-opus+ogg" = "com.github.neithern.g4music.desktop";
      "audio/x-pn-aiff" = "com.github.neithern.g4music.desktop";
      "audio/x-pn-au" = "com.github.neithern.g4music.desktop";
      "audio/x-pn-realaudio" = "com.github.neithern.g4music.desktop";
      "audio/x-pn-realaudio-plugin" = "com.github.neithern.g4music.desktop";
      "audio/x-pn-wav" = "com.github.neithern.g4music.desktop";
      "audio/x-pn-windows-acm" = "com.github.neithern.g4music.desktop";
      "audio/x-realaudio" = "com.github.neithern.g4music.desktop";
      "audio/x-real-audio" = "com.github.neithern.g4music.desktop";
      "audio/x-s3m" = "com.github.neithern.g4music.desktop";
      "audio/x-sbc" = "com.github.neithern.g4music.desktop";
      "audio/x-shorten" = "com.github.neithern.g4music.desktop";
      "audio/x-speex" = "com.github.neithern.g4music.desktop";
      "audio/x-stm" = "com.github.neithern.g4music.desktop";
      "audio/x-tta" = "com.github.neithern.g4music.desktop";
      "audio/x-wav" = "com.github.neithern.g4music.desktop";
      "audio/x-wavpack" = "com.github.neithern.g4music.desktop";
      "audio/x-vorbis" = "com.github.neithern.g4music.desktop";
      "audio/x-xm" = "com.github.neithern.g4music.desktop";
      "audio/x-mpegurl" = "com.github.neithern.g4music.desktop";
      "audio/x-scpls" = "com.github.neithern.g4music.desktop";

      # mpv for Video playback
      "video/x-ogm+ogg" = "mpv.desktop";
      "video/mpeg" = "mpv.desktop";
      "video/x-mpeg2" = "mpv.desktop";
      "video/x-mpeg3" = "mpv.desktop";
      "video/mp4v-es" = "mpv.desktop";
      "video/x-m4v" = "mpv.desktop";
      "video/mp4" = "mpv.desktop";
      "video/divx" = "mpv.desktop";
      "video/vnd.divx" = "mpv.desktop";
      "video/msvideo" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/ogg" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/vnd.rn-realvideo" = "mpv.desktop";
      "video/x-ms-afs" = "mpv.desktop";
      "video/x-ms-asf" = "mpv.desktop";
      "video/x-ms-wmv" = "mpv.desktop";
      "video/x-ms-wmx" = "mpv.desktop";
      "video/x-ms-wvxvideo" = "mpv.desktop";
      "video/x-avi" = "mpv.desktop";
      "video/avi" = "mpv.desktop";
      "video/x-flic" = "mpv.desktop";
      "video/fli" = "mpv.desktop";
      "video/x-flc" = "mpv.desktop";
      "video/flv" = "mpv.desktop";
      "video/x-flv" = "mpv.desktop";
      "video/x-theora" = "mpv.desktop";
      "video/x-theora+ogg" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/mkv" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/x-ogm" = "mpv.desktop";
      "video/mp2t" = "mpv.desktop";
      "video/vnd.mpegurl" = "mpv.desktop";
      "video/3gp" = "mpv.desktop";
      "video/3gpp" = "mpv.desktop";
      "video/3gpp2" = "mpv.desktop";
      "video/dv" = "mpv.desktop";
      "video/vnd.avi" = "mpv.desktop";
    };
  };

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
