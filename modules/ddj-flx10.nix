# Pioneer / AlphaTheta DDJ-FLX10 support.
#
# The jog-wheel LCDs show "NO AUDIO DRIVER" about three seconds after USB
# attach unless the host proves it speaks the AlphaTheta vendor protocol.
# A single read-only control transfer is enough:
#
#     bmRequestType 0xC0   bRequest 0x00   wIndex 0xC001   wLength 2
#
# which returns the firmware version (01 14 on firmware 1.14).  Nothing is
# ever written to the device.  Captured from the Windows driver stack and
# verified against the hardware; see
# /home/geza/VirtualDJ/midi-controller-investigation.md, "Gap 7".
{ pkgs, ... }:

let
  flx10-wake = pkgs.runCommandCC "flx10-wake" { } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -o $out/bin/flx10-wake ${./flx10-wake.c}
  '';
in
{
  # Handy for checking by hand: flx10-wake -v
  environment.systemPackages = [ flx10-wake ];

  # services.udev.extraRules is types.lines, so this merges with the rules
  # defined elsewhere rather than replacing them.
  services.udev.extraRules = ''
    # DDJ-FLX10: clear the jog screens' "NO AUDIO DRIVER" message on attach.
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", \
      ATTR{idVendor}=="2b73", ATTR{idProduct}=="0041", \
      RUN+="${flx10-wake}/bin/flx10-wake"
  '';
}
