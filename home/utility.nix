{ pkgs, lib, ... }:
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

    # Register [Alt + Space] hotkey for showing the Vicinae app
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      "binding" = "<Alt>space";
      "command" = "vicinae toggle";
      "name" = "Vicinae";
    };
  };

  # Start the Vicinae server right after activating the NixOS configuration
  home.activation.enableVicinae = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD systemctl --user enable vicinae.service --now || true
  '';

  # Start the Vicinae server when the systemd boots up.
  home.file.".config/systemd/user/graphical-session.target.wants/vicinae.service".source = "${pkgs.vicinae}/lib/systemd/user/vicinae.service";

  home.packages = with pkgs; [
    file # Determine the type of the given file
    htop # An interactive process viewer
    vicinae gnomeExtensions.vicinae # A focused launcher for your desktop — native, fast, extensible
  ];
}
