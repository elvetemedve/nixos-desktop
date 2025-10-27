# Install ependenceis for modern virtualization

{ config, pkgs, username, ... }:

{
  # Enable libvirt and KVM virtualization
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;  # TPM support for Windows 11
      runAsRoot = false;
    };
  };

  # Install the SPICE USB redirection helper to enable unprivileged user to pass USB devices to libvirt VMs.
  virtualisation.spiceUSBRedirection.enable = true;

  # Install virt-manager and related tools
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    win-virtio  # VirtIO drivers
    spice
    spice-gtk
    spice-protocol
  ];

  # Add your user to libvirtd group
  users.users."${username}" = {
    extraGroups = [ "libvirtd" ];
  };

  # Enable dnsmasq for libvirt networking
  virtualisation.libvirtd.extraConfig = ''
    unix_sock_group = "libvirtd"
    unix_sock_rw_perms = "0770"
  '';
}
