{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nerd-fonts.meslo-lg # Install "MesloLGS NF" font
    libnotify # Install the "notify-send" command
  ];
  fonts.fontconfig.enable = true;

  # Improved alternative to "cat" command
  programs.bat.enable = true;

  programs.bash.enable = true;
  programs.bash.initExtra = ''
    if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
    then
      shopt -q login_shell && LOGIN_OPTION="--login" || LOGIN_OPTION=""
      exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
    fi
  '';

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

