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
      "webgl.disabled" = false;
    };
  };
}

