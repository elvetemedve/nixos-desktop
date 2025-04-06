{ pkgs, ... }:
{
  home.packages = with pkgs; [
    inkscape # Vector graphics editor
    gimp # Graphics editor
    pinta # Simple raster graphics editor
  ];

  programs.helix = {
    enable = true;
    extraPackages = [ pkgs.wl-clipboard ];
    defaultEditor = true;
    settings = {
      editor = {
        line-number = "relative";
      };
      theme = "custom-default";
      keys.insert = {
        S-tab = "unindent";
      };
    };
    themes = {
      custom-theme = {
        inherits = "default";

        "ui.cursor.primary" = { fg = "#666666"; bg = "#ffffff"; };
      };
    };
  };
}

