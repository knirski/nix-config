{ pkgs, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "nvidia_drm.modeset=1"
      # Use deep S3 suspend instead of s2idle (S0ix). The NVIDIA driver has
      # a known S0ix timing issue where the GPU resumes before the USB-C dock
      # re-enumerates, causing "Failed to detect display state" errors and
      # external monitor loss. Deep S3 avoids this race entirely.
      "mem_sleep_default=deep"
    ];
    loader = {
      limine.enable = true;
      efi.canTouchEfiVariables = false;
    };
    initrd = {
      systemd.enable = true;
      availableKernelModules = [
        "tpm_crb"
        "nvme"
        "xhci_pci"
        "uas"
        "sd_mod"
      ];
      luks.devices.crypted = {
        device = "/dev/disk/by-partlabel/luks";
        allowDiscards = true;
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      };
    };
  };

  zramSwap.enable = true;
  security.tpm2.enable = true;
  services.hardware.bolt.enable = true;
}
