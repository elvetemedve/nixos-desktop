{ pkgs, ... }:
{
  # Install the Firefox web browser
  programs.firefox = {
    enable = true;
    languagePacks = [
      "en-GB"
      "hu"
    ];
    profiles."geza" = {
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
        "identity.fxaccounts.toolbar.enabled" = false; # Remove Mozilla Monitor from the toolbar
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.history" = false;
        "privacy.clearOnShutdown.downloads" = false;
        "webgl.disabled" = false;
      };
    };
  };
}
