{ pkgs, ... }:
{
  home.packages = with pkgs; [
    audacious # Winmap alike music player
    audacity # Audio editor
    gapless # Lightweight GTK4 music player (a.k.a. g4music)
    nicotine-plus # A graphical client for Soulseek
    picard # Music file tagger
    streamrip # Music downloader
  ];
}
