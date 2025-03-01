{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # LibreOffice free and private office suite.
    # Includes Writer (word processing), Calc (spreadsheets), Impress (presentations), Draw (vector graphics and flowcharts), Base (databases), and Math (formula editing).
    libreoffice-fresh 
  ];
}
