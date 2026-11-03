{ ... }:

# Custom KDE Plasma keyboard shortcuts (written by plasma-manager into
# ~/.config/kglobalshortcutsrc). Mirrors the GNOME hotkeys in utility.nix.
# Only the listed shortcuts are managed; other KDE defaults stay untouched.
{
  programs.plasma = {
    enable = true;

    shortcuts = {
      # Layout switching: us <-> hu
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" = "Meta+Space";

      # Free Alt+Space (KRunner default) for Vicinae, keep Alt+F2
      "services/org.kde.krunner.desktop"._launch = "Alt+F2";
    };

    # Keyboard layouts, first one is the default (switch with Meta+Space)
    input.keyboard = {
      layouts = [
        { layout = "us"; }
        { layout = "hu"; }
      ];
    };

    # Touchpads attached to every host (vendor/product IDs are hex, see
    # ~/.config/kcminputrc or libinput list-devices). Built-in touchpads are
    # configured per host.
    input.touchpads = [
      {
        name = "Logitech Rechargeable Touchpad T650";
        vendorId = "046d";
        productId = "4101";
        naturalScroll = true;
      }
    ];

    hotkeys.commands = {
      vicinae-toggle = {
        name = "Vicinae";
        key = "Alt+Space";
        command = "vicinae toggle";
      };
      vicinae-clipboard = {
        name = "Show clipboard history";
        key = "Ctrl+Alt+H";
        command = "vicinae deeplink vicinae://launch/clipboard/history";
      };
      vicinae-windows = {
        name = "Show switch windows";
        key = "Ctrl+Alt+W";
        command = "vicinae deeplink vicinae://launch/wm/switch-windows";
      };
      vicinae-emojis = {
        name = "Show emojis";
        key = "Ctrl+Alt+E";
        command = "vicinae deeplink vicinae://launch/core/search-emojis";
      };
      vicinae-translate = {
        name = "Show language translator";
        key = "Ctrl+Alt+T";
        command = "vicinae deeplink vicinae://launch/@elvetemedve/libretranslate/translate";
      };
      whisrs-toggle = {
        name = "Start or stop voice dictation";
        key = "Meta+Microphone Mute";
        command = "whisrs toggle";
      };
    };
  };
}
