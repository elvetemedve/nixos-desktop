{ username, lib, osConfig, pkgs, ... }:
{
  home.file."ssh-config" = {
    source = ./storage/ssh-config;
    target = ".ssh/config";
  };
  home.packages = with pkgs; [
    sshfs # Utility to mount SSH connection as filesystem
  ];

  services.syncthing = {
    enable = true;
    settings = {
      devices = {
        "home-server" = {
          id = "4VYBKJG-ZWMPLML-ZPS4INJ-SWQGANE-JW4GRMH-R2ZDQJV-P4RXCAP-DHWBIA4";
          name = "Home Server";
        };
        "smartphone" = {
          id = "JXHPBOZ-OKJMZOI-WQAZJT6-2UEAFBM-TCU2KD4-PRUKORF-M5SJ4ZI-27FMIQU";
          name = "Geza's Samsung Galaxy S24 Ultra";
        };
      };
      folders = {
        "/home/${username}/KeePassXC" = {
          id = "keepass";
          devices = [ "smartphone" "home-server" ];
          label = "KeePassXC";
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };
      } // lib.attrsets.optionalAttrs (builtins.hasAttr "/mnt/music" osConfig.fileSystems) { # Apply the following settings where /mnt/music is a mount point
        "/mnt/music/albums" = {
          id = "music-albums-for-djing";
          ignorePerms = true; # Do not sync file permissions as FAT does not support it
          devices = [ "home-server" ];
          label = "Music albums for DJing";
          rescanIntervalS = 86400; # The rescan interval, in seconds
          type = "receiveonly"; # Local file change is not synced
        };
        "/mnt/music/singles" = {
          id = "music-singles-for-djing";
          ignorePerms = true; # Do not sync file permissions as FAT does not support it
          devices = [ "home-server" ];
          label = "Music singles for DJing";
          rescanIntervalS = 86400; # The rescan interval, in seconds
          type = "receiveonly"; # Local file change is not synced
        };
      };

    };
  };

  systemd.user.automounts."home-${username}-home_server" = {
    Unit = {
      Description = "Automount ~/home_server";
    };

    Automount = {
      Where = "/home/${username}/home_server";
      TimeoutIdleSec = "5min";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
  
  systemd.user.mounts."home-${username}-home_server" = {
    Unit = {
      Description = "SSHFS (Home Server)";
      Before = "remote-fs.target";
    };

    Mount = {
      What = "${username}@nixos.lan:/mnt/storage";
      Where = "/home/${username}/home_server";
      Type = "fuse.sshfs";
      Options = [ "_netdev" "rw" "nosuid" "default_permissions" "allow_other" "follow_symlinks" "idmap=user" "ServerAliveInterval=10" "ServerAliveCountMax=1" "ConnectTimeout=3" ];
      ForceUnmount = true;
      DirectoryMode = "0700";
      TimeoutSec = 10;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

}

