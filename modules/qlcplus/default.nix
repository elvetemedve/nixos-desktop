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
#
# With the beat generator set to Plugin, upstream works the BPM out from the
# time between OS2L beats, which QLC+ only handles on its 20 ms timer ticks:
# 140 BPM reads as anything from 136 to 143. ./os2l-bpm.patch uses the "bpm"
# VirtualDJ sends with each beat instead, rounded to a whole number (QLC+
# keeps it as one); the beats themselves still advance beat-tempo functions.
#
# QLC+ drives USB DMX adapters (FTDI and others) through libftdi/libusb on the
# raw /dev/bus/usb node, not /dev/ttyUSB*, so the dialout group is not enough:
# the udev rules the package ships open those nodes up to all users.
{ pkgs, ... }:
let
  qlcplus = pkgs.callPackage ./package.nix { };
in
{
  environment.systemPackages = [ qlcplus ];
  services.udev.packages = [ qlcplus ];
}
