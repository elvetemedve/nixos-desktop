{ pkgs, ... }:
{
  home.packages = with pkgs; [
    audacious # Winmap alike music player
    gapless # Lightweight GTK4 music player (a.k.a. g4music)
  ];
}
