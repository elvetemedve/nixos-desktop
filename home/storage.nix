{ username, lib, osConfig, pkgs, ... }:
{
  home.file."ssh-config" = {
    source = ./storage/ssh-config;
    target = ".ssh/config";
  };

  services.syncthing = {
    enable = true;
    settings = {
      devices = {
        "home-server" = {
          id = "4VYBKJG-ZWMPLML-ZPS4INJ-SWQGANE-JW4GRMH-R2ZDQJV-P4RXCAP-DHWBIA4";
          name = "Home Server";
        };
        "smartphone" = {
          id = "H4CYTW5-I7BCI6P-TEF56UK-QY3X3TD-HWU4S6Q-DMXBHR7-6BDFVF5-O735FQO";
          name = "Geza's Galaxy S24 Ultra";
        };
      };
      folders = {
        "/home/${username}/Documents" = {
          id = "home-documents";
          devices = [ "home-server" ];
          label = "Documents";
          rescanIntervalS = 86400; # The rescan interval, in seconds
          versioning = {
            type = "simple";
            params.keep = "2";
          };
        };
        "/home/${username}/KeePassXC" = {
          id = "keepass";
          devices = [ "smartphone" "home-server" ];
          label = "KeePassXC";
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };
        "/home/${username}/Pictures" = {
          id = "home-pictures";
          devices = [ "home-server" ];
          label = "Pictures";
          rescanIntervalS = 86400; # The rescan interval, in seconds
          versioning = {
            type = "simple";
            params.keep = "2";
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

}
