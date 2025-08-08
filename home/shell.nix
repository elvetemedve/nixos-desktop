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

  # Highly configurable system information fetching CLI tool
  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        type = "builtin";
        source = "nixos";
        padding = {
          right = 2;
        };
        color = {
          "1" = "blue";
        };
      };
      display = {
        separator = "  ";
        color = {
          keys = "blue";
        };
      };
      modules = [
        "title"
        "separator"
        {
          type = "os";
          key = "OS";
        }
        {
          type = "kernel";
          key = "Kernel";
        }
        {
          type = "uptime";
          key = "Uptime";
        }
        {
          type = "bios";
          key = "BIOS";
        }
        {
          type = "de";
          key = "DE";
        }
        {
          type = "shell";
          key = "Shell";
        }
        {
          type = "terminal";
          key = "Terminal";
        }
        {
          type = "packages";
          key = "Packages";
        }
        {
          type = "cpu";
          key = "CPU";
        }
        {
          type = "gpu";
          key = "GPU";
        }
        {
          type = "memory";
          key = "Memory";
        }
        "break"
        {
          type = "disk";
          key = "Disk";
          format = "{name} - {size-used} / {size-total} [{size-percentage}]";
          folders = [
            "/"
          ];
        }
        {
          type = "wifi";
          key = "WiFi";
        }
        {
          type = "player";
          key = "Media Player";
        }
        {
          type = "media";
          key = "Currently Playing";
        }
      ];
    };
  };

  # Enable and confgure Fish shell
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      gpg-connect-agent /bye
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)

      set fish_greeting # Disable greeting

      # Configure the Tide plugin
      set --universal tide_left_prompt_items context os pwd git newline character
      set --universal tide_right_prompt_items status cmd_duration jobs direnv node python rustc java php pulumi ruby go gcloud distrobox toolbox terraform aws nix_shell crystal elixir zig time
      set --universal tide_context_always_display true # Display user@hostname in the prompt always
      set --universal _tide_left_items $tide_left_prompt_items
      set --universal _tide_right_items $tide_right_prompt_items

      # Display system info
      ${pkgs.fastfetch}/bin/fastfetch
    '';
    loginShellInit = ''
      tide configure --auto --style=Rainbow --prompt_colors='True color' --show_time='24-hour format' --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat --powerline_prompt_style='Two lines; character' --prompt_connection=Solid --powerline_right_prompt_frame=No --prompt_connection_andor_frame_color=Lightest --prompt_spacing=Compact --icons='Many icons' --transient=Yes
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

