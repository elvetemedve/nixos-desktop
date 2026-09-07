{ lib, pkgs, ... }:

let
  # Kernel params shared by both eGPU specialisations.
  # 
  # Variable-isolation result for the NVIDIA bug report (issue #979 follow-up):
  #  - pci=realloc : REQUIRED, and orthogonal to the hang - it's about MMIO,
  #    not link training. Without it the GPU's bridge windows can't be
  #    assigned behind the tunnel ("bridge window [mem size 0x24100000
  #    64bit pref]: can't assign; no space" on 0000:21:00.0) and the driver
  #    never loads.
  egpuKernelParams = [ "pci=realloc" ];

  # NVreg_DynamicPowerManagement=0 - don't let the driver drop the eGPU into
  # runtime D3; the Thunderbolt link can't reliably bring it back.
  egpuModprobe = ''
    options nvidia NVreg_DynamicPowerManagement=0x00
  '';
in
{
  imports = [ ./blackwell-egpu-manager.nix ];

  # AORUS RTX 5060 Ti AI BOX is not supported by nouveau driver, disable it to be safe.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Full eGPU: drives displays (HDMI-to-TV) and does compute. This is the one
  # that hard-freezes the machine on first GPU use until the link is stable,
  # because mutter adopts the eGPU as a KMS device.
  specialisation.egpu.configuration = {
    system.nixos.label = "egpu";

    boot.kernelPackages = pkgs.linuxPackages_7_1;

    boot.kernelParams = egpuKernelParams;
    boot.extraModprobeConfig = egpuModprobe;

    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      open = true;
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

    # Community tool that immediately kicks the eGPU's known bridge chips off
    # the bus on hotplug/coldplug (udev), then manually disables ASPM/L1SS and
    # forces a PCIe retrain on every bridge in the chain *before* nvidia ever
    # touches the device. Targets this exact hardware (its udev rule literally
    # matches "Intel Barlow Ridge (AORUS TB5)", 8086:5786) - see
    # modules/blackwell-egpu-manager.nix. Use: `blackwell-egpu status`,
    # `sudo blackwell-egpu set 3` (hybrid offload - what PRIME here needs).
    programs.blackwellEgpuManager.enable = true;
  };
}
