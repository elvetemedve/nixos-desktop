{ lib, pkgs, ... }:

let
  # Kernel params shared by both eGPU specialisations.
  #
  # pci=realloc            - the Thunderbolt bridge can't size the GPU's BARs otherwise.
  # pcie_aspm.policy=...    - the eGPU throws a PCIe completion timeout and "falls off
  #                          the bus" the moment it is used; disable ASPM link power
  #                          states. policy=performance keeps native _OSC PCIe control
  #                          (unlike pcie_aspm=off, which makes the firmware withhold
  #                          hotplug/PME/AER and parks the GPU in D3cold).
  # pcie_port_pm=off        - don't runtime-suspend the Thunderbolt PCIe port.
  #
  # Do NOT add iommu=pt: this laptop's firmware force-enables the IOMMU for
  # Thunderbolt DMA protection, and a passthrough domain breaks the GPU's GSP
  # firmware message channel (kgspInitRm hangs with no error, GPU still in D0).
  #
  # Do NOT add pci=assign-busses / hpbussize / hpmmiosize / hpmmioprefsize here:
  # hpbussize exhausts the PCI bus-number space behind the box's internal switch
  # ("devices behind bridge are unusable because [bus ..] cannot be assigned"),
  # which trips a NULL-deref bug in the kernel's of_pci_prop_bus_range() during
  # PCIe hotplug (crash in of_pci_add_properties, irq/NN-pciehp).
  # Root cause (confirmed against Windows/GPU-Z): the Thunderbolt PCIe tunnel
  # trains at Gen1 (2.5 GT/s x4) on Linux - `pci 0000:22:00.0: ... limited by
  # 2.5 GT/s PCIe x4 link at 0000:00:07.0` - where Windows gets Gen4 x4. At 1/8
  # the bandwidth (plus config-access stalls) the GPU's GSP firmware init never
  # completes. Resizable BAR is a red herring: Windows runs with ReBAR disabled
  # and a 256 MB BAR1 and works fine.
  egpuKernelParams = [
    "pci=realloc"
    "pcie_aspm.policy=performance"
    "pcie_port_pm=off"
  ];

  # NVreg_DynamicPowerManagement=0 - don't let the driver drop the eGPU into
  # runtime D3; the Thunderbolt link can't reliably bring it back.
  #
  # NVreg_EnableGpuFirmwareLogs was dropped: it needs gsp_log_ga10x.bin, which
  # nixpkgs' nvidia-x11 firmware package does not ship (only gsp_ga10x.bin), so
  # it just logs "Direct firmware load ... failed with error -2" - harmless, and
  # unrelated to the GSP init hang.
  egpuModprobe = ''
    options nvidia NVreg_DynamicPowerManagement=0x00
  '';
in
{
  # nouveau fails to init the eGPU's GSP firmware and can wedge suspend/resume
  # (s2idle) if the eGPU is unplugged while the laptop is asleep.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Full eGPU: drives displays (HDMI-to-TV) and does compute. This is the one
  # that hard-freezes the machine on first GPU use until the link is stable,
  # because mutter adopts the eGPU as a KMS device.
  specialisation.egpu.configuration = {
    system.nixos.label = "egpu";

    # 6.18 leaves the Thunderbolt PCIe tunnel stuck at Gen1; newer USB4/PCIe
    # bandwidth-controller code is the best shot at getting it to Gen4.
    # (linux_6_19 asked for but it's already EOL/removed from this nixpkgs.)
    boot.kernelPackages = pkgs.linuxPackages_7_1;

    boot.kernelParams = egpuKernelParams;
    boot.extraModprobeConfig = egpuModprobe;

    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      open = true;
      # 610 branch - much fresher Blackwell (GB206) / Thunderbolt handling than
      # the 595 production branch.
      branch = "latest";
      modesetting.enable = true;
      powerManagement.finegrained = false;
      prime = {
        offload.enable = true;
        offload.enableOffloadCmd = true;
        allowExternalGpu = true;
        intelBusId  = "PCI:0:2:0";
        nvidiaBusId = "PCI:34:0:0";
      };
    };
  };

  # Compute-only eGPU: fully headless (no GDM/GNOME/Xorg), driver loads as a CUDA
  # device with NO KMS. A GPU fault kills the offending process, not the box.
  #
  # IMPORTANT: cold-booting with the eGPU attached hard-freezes udev coldplug on
  # the marginal in-enclosure PCIe config access. Always boot WITHOUT the box,
  # reach the TTY, THEN plug it in, then `nvidia-smi` / run CUDA.
  specialisation.egpu-compute.configuration = {
    system.nixos.label = "egpu-compute";

    boot.kernelPackages = pkgs.linuxPackages_7_1;
    boot.kernelParams = egpuKernelParams;
    boot.extraModprobeConfig = egpuModprobe;

    # Boot to a text console - GDM/GNOME never start, so nothing touches the GPU
    # until an explicit CUDA run. `systemctl isolate graphical.target` to get the
    # desktop later if wanted.
    systemd.defaultUnit = lib.mkForce "multi-user.target";

    # Drive the test from another machine with `journalctl -kf` running - if that
    # SSH session dies mid-stream, it was a real kernel hang.
    services.openssh.enable = true;

    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      open = true;
      branch = "latest";
      modesetting.enable = false;
      nvidiaSettings = false;
      prime.offload.enable = lib.mkForce false;
      prime.sync.enable = lib.mkForce false;
    };
  };
}
