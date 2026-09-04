# Packages https://github.com/DamianKA1993/blackwell-egpu-manager for NixOS.
#
# Upstream's install.sh assumes a writable FHS: it `sudo cp`s the CLI to
# /usr/local/bin, writes /etc/sudoers.d and /etc/udev/rules.d directly, and
# `cp -r`s the GNOME extension into ~/.local/share. None of that survives a
# NixOS rebuild (and the /etc writes fail outright). This module builds the
# CLI as a normal derivation and reproduces the rest of what install.sh does
# declaratively: a udev-managed immediate-remove-on-add rule for known eGPU
# bridge chips (so nothing touches them mid-tunnel-negotiation, including the
# udev coldplug pass that hangs at cold boot - see modules/egpu.nix), a
# passwordless sudo rule scoped to the one binary (the GNOME extension shells
# out to `sudo blackwell-egpu ...`), and tmpfiles symlinks so the hardcoded
# /usr/local/bin path and the GNOME extension search path resolve to it.
{ config, lib, pkgs, inputs, username, ... }:

let
  cfg = config.programs.blackwellEgpuManager;

  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "blackwell-egpu-manager";
    version = "1.5.4";
    src = inputs.blackwell-egpu-manager;

    dontBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall

      install -Dm755 blackwell-egpu "$out/bin/blackwell-egpu"

      mkdir -p "$out/share/gnome-shell/extensions"
      cp -r "gnome-applet/blackwell-egpu@com.github.blackwellegpu" \
            "$out/share/gnome-shell/extensions/blackwell-egpu@com.github.blackwellegpu"

      runHook postInstall
    '';

    # nvidia-smi is deliberately left off this PATH - it must resolve to
    # whichever driver build is actually active in the specialisation.
    #
    # No glxinfo (mesa-demos): it's only used for one cosmetic device-name
    # label at first run and the script already falls back cleanly without it.
    postFixup = ''
      wrapProgram "$out/bin/blackwell-egpu" --prefix PATH : ${lib.makeBinPath (with pkgs; [
        pciutils # lspci, setpci
        bolt # boltctl
        kmod # modprobe
        psmisc # fuser
        util-linux
        coreutils
        gnugrep
        gnused
        gawk
      ])}
    '';

    meta.mainProgram = "blackwell-egpu";
  };

  extensionUuid = "blackwell-egpu@com.github.blackwellegpu";
in
{
  options.programs.blackwellEgpuManager = {
    enable = lib.mkEnableOption "blackwell-egpu-manager (community Thunderbolt PCIe retrainer / mode manager for Blackwell eGPUs)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package ];

    systemd.tmpfiles.rules = [
      "L+ /usr/local/bin/blackwell-egpu - - - - ${package}/bin/blackwell-egpu"
      "L+ /home/${username}/.local/share/gnome-shell/extensions/${extensionUuid} - - - - ${package}/share/gnome-shell/extensions/${extensionUuid}"
    ];

    # The GNOME extension always invokes `sudo /usr/local/bin/blackwell-egpu ...`.
    security.sudo.extraRules = [{
      users = [ username ];
      commands = [{
        command = "/usr/local/bin/blackwell-egpu";
        options = [ "NOPASSWD" ];
      }];
    }];

    # Verbatim from upstream's udev/99-blackwell-egpu.rules: immediately kick
    # these PCI IDs off the bus on ACTION=="add" unless /tmp/egpu_allow exists.
    # `blackwell-egpu set 3` creates that flag, retrains the link (ASPM/L1SS
    # off, forced LnkCtl2 target speed + retrain) on every bridge in the
    # chain, *then* rescans - so nvidia/coldplug only ever see the device
    # after the tunnel has been brought up deliberately, not mid-negotiation.
    services.udev.extraRules = ''
      # Intel Barlow Ridge (AORUS TB5)
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST!="/tmp/egpu_allow", ATTR{remove}="1"
      # ASMedia ASM2464PD (USB4)
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", ATTR{device}=="0x2464", TEST!="/tmp/egpu_allow", ATTR{remove}="1"
      # Intel Goshen / Titan Ridge (TB3/TB4)
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15eb", TEST!="/tmp/egpu_allow", ATTR{remove}="1"
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x0b26", TEST!="/tmp/egpu_allow", ATTR{remove}="1"
    '';
  };
}
