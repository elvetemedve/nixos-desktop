{ ... }:
{
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
        "/home/geza/KeePassXC" = {
          id = "keepass";
          devices = [ "smartphone" "home-server" ];
          label = "KeePassXC";
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };
      };
    };
  };
}

