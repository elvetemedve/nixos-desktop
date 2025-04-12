{ pkgs, ... }:
{
  home.packages = with pkgs; [
    webtorrent_desktop # Play videos by streaming from torrent files
  ];
}
