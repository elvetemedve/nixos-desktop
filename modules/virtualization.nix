# Install ependenceis for modern virtualization

{ config, pkgs, username, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_latest; # Use the latest stable kernel version

  boot.kernelParams = [ 
    "intel_iommu=on" 
    "iommu=pt"
    "amdgpu.runpm=0" # Workaround for a power management bug with GMKtec AD-GP1 AMD Radeon 7600M XT
    "vfio-pci.ids=1002:7480,1002:ab30"
  ];

  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"

    "i915"
  ];

  # Workaround for power management issues when vfio-pci driver is used
  # Optional: ATTR{power/control}="on"
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x7480", ATTR{d3cold_allowed}="0"
  '';

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
    virtio-win  # VirtIO drivers
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
