# PipeASIO reads $XDG_CONFIG_HOME/pipeasio/config.ini (falling back to
# ~/.config/pipeasio/config.ini). Managing it here gives a from-scratch
# prefix the right channel counts and buffer size with no manual copy.
{ ... }:
{
  xdg.configFile."pipeasio/config.ini".source = ./virtualdj-pipeasio-config.ini;
}
