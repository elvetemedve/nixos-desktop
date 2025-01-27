{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nerd-fonts.meslo-lg # Install "MesloLGS NF" font
    libnotify # Install the "notify-send" command
  ];
  fonts.fontconfig.enable = true;

  # Improved alternative to "cat" command
  programs.bat.enable = true;

  # Enable and confgure Fish shell
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
      gpg-connect-agent /bye
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
    '';
    plugins = [
      {
        name = "tide"; 
        src = pkgs.fishPlugins.tide.src;
      }
      {
        name = "fzf";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "done";
        src = pkgs.fishPlugins.done.src;
      }
    ];
  };

  # User-friendly alternative to "find" command
  programs.fd.enable = true;

  # Enable fuzzy search in lists
  programs.fzf.enable = true;
}

