# QLC+ as the OS2L light show for VirtualDJ.
#
# Upstream QLC+ advertises OS2L feedback but never implements it: it never
# writes back to VirtualDJ, so an `os2l_button` pad stays dark however the
# button in QLC+ ends up. ./os2l-feedback.patch adds that:
#
#   - the OS2L plugin keeps its VirtualDJ connections and answers with
#     {"evt":"feedback","name":...,"state":"on"|"off"}, the name taken from
#     the OS2L input profile channel (or, without one, from the button
#     messages VirtualDJ sent so far);
#   - once a button has had feedback, VirtualDJ stops sending a press and a
#     release: each press is one message carrying the state it wants (the
#     opposite of the last feedback). The plugin turns such a change of
#     state into a press and release, so the button still toggles;
#   - a QML Virtual Console Blackout button follows the actual blackout
#     state, rather than going on and off with each press, so what VirtualDJ
#     shows is whether the lights are blacked out.
#
# Feedback is per universe: in QLC+'s Inputs/Outputs view, enable the "F"
# toggle next to the universe's OS2L input.
{ pkgs, ... }:
{
  environment.systemPackages = [ (pkgs.callPackage ./package.nix { }) ];
}
