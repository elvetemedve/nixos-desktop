{ pkgs, ... }:
{
  home.packages = with pkgs; [
    magic-wormhole # Securely transfer data between computers
  ];

  # KeePassXC offline password manager
  programs.keepassxc = {
    autostart = true;
    enable = true;
    settings = {
      Browser.Enabled = true;
      Browser.UpdateBinaryPath = false;

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

