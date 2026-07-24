{ pkgs, ... }:
{
  # Install Ghostty terminal emulator application
  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      font-family = "ghostty +list-fonts";
      font-size = "13";
      keybind = "performable:ctrl+v=paste_from_clipboard";
      maximize = true;
      shell-integration-features = "ssh-env,ssh-terminfo";
    };
  };
}

