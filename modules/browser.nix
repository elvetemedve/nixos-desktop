{ config, ... }:
let
  lock-false = {
    Value = false;
    Status = "locked";
  };
in {
  programs.firefox = {
    enable = true;
    policies = {
      "DisableTelemetry" = true;
      "DisableFirefoxStudies" = true;
      "DisablePocket" = true;
      
      "Preferences" = {
        "browser.startup.page" = 3; # Open previous windows and tabs
        "extensions.pocket.enabled" = lock-false;
        "browser.topsites.contile.enabled" = lock-false;
        "browser.newtabpage.activity-stream.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;
      };

      ExtensionSettings = {
        # KeePassXC-Browser
        "keepassxc-browser@keepassxc.org" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
          installation_mode = "force_installed";
        };

        # Cookie Quick Manager
        "{60f82f00-9ad5-4de5-b31c-b16a47c51558}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/cookie-quick-manager/latest.xpi";
          installation_mode = "force_installed";
        };

        # I don't care about cookies
        "jid1-KKzOGWgsW3Ao4Q@jetpack" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/i-dont-care-about-cookies/latest.xpi";
          installation_mode = "force_installed";
        };

        # uBlock Origin
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };

        # Nimbus Screen Capture: Screenshots, Annotate
        "nimbusscreencaptureff@everhelper.me" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/nimbus-screenshot/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };
  };
}

