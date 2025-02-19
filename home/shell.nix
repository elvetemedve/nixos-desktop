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

      # Configure the Tide plugin
      set --universal tide_left_prompt_items context os pwd git newline character
      set --universal tide_right_prompt_items status cmd_duration jobs direnv node python rustc java php pulumi ruby go gcloud kubectl distrobox toolbox terraform aws nix_shell crystal elixir zig time
      set --universal tide_context_always_display true # Display user@hostname in the prompt always

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
    shellAliases = {
      cat = "bat";
    };
  };

  # User-friendly alternative to "find" command
  programs.fd.enable = true;

  # Enable fuzzy search in lists
  programs.fzf.enable = true;
}

