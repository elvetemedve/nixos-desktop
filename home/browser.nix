{ ... }:
{
  # Install the LibreWolf web browser
  programs.librewolf = {
    enable = true;
    languagePacks = [
      "en-GB"
      "hu"
    ];
    settings = {
      "privacy.clearOnShutdown.cookies" = false;
      "privacy.clearOnShutdown.history" = false;
      "privacy.clearOnShutdown.downloads" = false;
      "webgl.disabled" = false;
    };
  };
}

