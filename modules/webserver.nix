# Install reverse proxy to server local web services

{ config, pkgs, ... }:

{
  services.caddy = {
    enable = true;
    virtualHosts = {
      "http://syncthing.localhost" = {
        extraConfig = ''
          reverse_proxy http://localhost:8384
        '';
      };
    };
  };
}
