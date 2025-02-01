{ pkgs, ... }:
{
  # Install the LibreWolf web browser
  programs.firefox = {
    enable = true;
    languagePacks = [
      "en-GB"
      "hu"
    ];
    profiles."geza" = {
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        cookie-quick-manager
        i-dont-care-about-cookies
        keepassxc-browser
        ublock-origin
      ];
      search = {
        default = "SearXNG";
        engines = {
          "SearXNG" = {
            urls = [{ template = "https://search.elvetemedve.hu/search?q={searchTerms}"; }];
          };
        };
        force = true;
      };
      settings = {
        "browser.startup.page" = 3; # Open previous windows and tabs
        "extensions.pocket.enabled" = false; # Disable "Pocket"
        "identity.fxaccounts.toolbar.enabled" = false; # Remove Mozilla Monitor from the toolbar
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.history" = false;
        "privacy.clearOnShutdown.downloads" = false;
        "webgl.disabled" = false;
      };
    };
  };
}
