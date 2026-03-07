{ pkgs, vicinae-extensions, ... }:
{
  dconf.settings = {
    # Disable [Alt + Space] hotkey for activating the actual window menu
    "org/gnome/desktop/wm/keybindings" = {
      activate-window-menu = [ "" ];
    };

    # Install the companion Gnome Shell Extension to provide window management and clipboard access
    "org/gnome/shell" = {
      enabled-extensions = [ "vicinae@dagimg-dot" ];
    };

    # Register [Alt + Space] hotkey for showing the Vicinae launcher
    # Register [Control + Alt + h] hotkey for showing the Vicinae clipboard history
    # Register [Control + Alt + w] hotkey for showing the Vicinae switch windows panel
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      "binding" = "<Alt>space";
      "command" = "vicinae toggle";
      "name" = "Vicinae";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      "binding" = "<Control><Alt>h";
      "command" = "vicinae deeplink vicinae://extensions/vicinae/clipboard/history";
      "name" = "Show clipboard history";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      "binding" = "<Control><Alt>w";
      "command" = "vicinae deeplink vicinae://extensions/vicinae/wm/switch-windows";
      "name" = "Show switch windows";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3" = {
      "binding" = "<Control><Alt>e";
      "command" = "vicinae deeplink vicinae://extensions/vicinae/core/search-emojis";
      "name" = "Show emojis";
    };
  };

  home.packages = with pkgs; [
    file # Determine the type of the given file
    htop # An interactive process viewer
    gnomeExtensions.vicinae # Gnome extension for Vicinae - focused launcher for your desktop
  ];

  services.vicinae = {
    enable = true;
    systemd = {
      enable = true;
      autoStart = true;
      environment = {
        USE_LAYER_SHELL = 1;
      };
    };
    extensions = with vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      # Extension names can be found in the link below, it's just the folder names
      # https://github.com/vicinaehq/extensions/tree/main/extensions
      dashboard-icons
      firefox
      fuzzy-files
      github
      gnome-dnd
      gnome-settings
      html-symbol-finder
      nix
      power-profile
      process-manager
      pulseaudio
    ];
  };
}
