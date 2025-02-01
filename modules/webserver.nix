# Install reverse proxy to server local web services

{ config, pkgs, ... }:

{
  services.caddy = {
    enable = true;
    virtualHosts = {
      "syncthing.localhost" = {
        extraConfig = ''
          reverse_proxy http://localhost:8384
        '';
        serverAliases = [ "syncthing" ];
      };
    };
  };
}
