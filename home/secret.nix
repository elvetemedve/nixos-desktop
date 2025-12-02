{ pkgs, ... }:
{
  home.packages = with pkgs; [
    magic-wormhole # Securely transfer data between computers
  ];

  # KeePassXC offline password manager
  # For available settings, see https://github.com/keepassxreboot/keepassxc/blob/develop/src/core/Config.cpp
  programs.keepassxc = {
    autostart = true;
    enable = true;
    settings = {
      Browser.Enabled = true;
      Browser.UpdateBinaryPath = false;
      Browser.SearchInAllDatabases = true; # Search in all open databases for matching credentials

      FdoSecrets.Enabled = true;

      GUI = {
        AdvancedSettings = true;
        ApplicationTheme = "dark";
        CompactMode = true;
        HidePasswords = true;
      };

      SSHAgent.Enabled = true;
    };
  };

  xdg.autostart.enable = true; # Whether to enable creation of XDG autostart entries.
}

