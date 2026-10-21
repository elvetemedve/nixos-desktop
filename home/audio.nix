{ pkgs, ... }:
{
  home.packages = with pkgs; [
    audacious # Winmap alike music player
    # Disable installation of Audacity 4 temporarily as the build is failing at the moment 2026-10-21.
    #audacity # Audio editor
    gapless # Lightweight GTK4 music player (a.k.a. g4music)
    nicotine-plus # A graphical client for Soulseek
    picard # Music file tagger
    streamrip # Music downloader
  ];
}
