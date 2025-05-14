{ pkgs, ... }:
{
  home.packages = with pkgs; [
    mpv # General-purpose media player, fork of MPlayer and mplayer2
    webtorrent_desktop # Play videos by streaming from torrent files
  ];
}
