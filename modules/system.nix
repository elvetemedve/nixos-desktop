# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  boot.kernel.sysctl = {
    "net.ipv4.icmp_echo_ignore_broadcasts" = 0; # Enable receiving broadcast messages on IPv4
  };

  # Bootloader.
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 15; # Limit the number of boot entries
    consoleMode = "max"; # Adjust boot screen resolution for HiDPI monitor
    editor = false; # Disable editing the boot entries for security protection
  };

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Budapest";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "hu_HU.UTF-8";
    LC_IDENTIFICATION = "hu_HU.UTF-8";
    LC_MEASUREMENT = "hu_HU.UTF-8";
    LC_MONETARY = "hu_HU.UTF-8";
    LC_NAME = "hu_HU.UTF-8";
    LC_NUMERIC = "hu_HU.UTF-8";
    LC_PAPER = "hu_HU.UTF-8";
    LC_TELEPHONE = "hu_HU.UTF-8";
    LC_TIME = "hu_HU.UTF-8";
  };

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Install fwup daemon and user space client, for managing device firmware updates.
  services.fwupd.enable = true;
  
  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.geza = {
    isNormalUser = true;
    description = "Géza Búza";
    extraGroups = [ "networkmanager" "wheel" ];
    uid = 1000;
  };

  # Install Git version manager
  programs.git.enable = true;

  # Setup Gnupg for SSH authentication
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Garbage collect unused/old profiles and packages
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Enable the Flakes feature and the accompanying new nix command-line tool
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    helix # Post-modern modal text editor.
    pciutils # Install CLI commands like lspci
    pwvucontrol # Pipewire Volume Control tool.
    gnome-network-displays # Miracast implementation for GNOME Desktop
    usbutils # Install CLI commands like lsusb
    lshw # Display hardware information report
  ];

  # Set Helix as default text editor
  environment.variables."EDITOR" = "hx";

  # Enable Wayland mode for QT framework based applications to display UI correctly.
  environment.variables."QT_QPA_PLATFORM" = "wayland";

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
