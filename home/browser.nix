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

        # Preserve data after closing the browser
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.history" = false;
        "privacy.clearOnShutdown.downloads" = false;
        "privacy.clearOnShutdown.siteSettings" = false;
        "privacy.clearOnShutdown_v2.cookiesAndStorage" = false;
        "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = false;
        "privacy.clearOnShutdown_v2.siteSettings" = false;
        "privacy.sanitize.sanitizeOnShutdown" = false;
        "webgl.disabled" = false;
      };
    };
  };
}
