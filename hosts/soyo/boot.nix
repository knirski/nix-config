{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap.enable = true;
  security.tpm2.enable = true;

  boot.loader.limine.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [
    "tpm_crb"
    "nvme"
    "xhci_pci"
    "uas"
    "sd_mod"
  ];

  # Phase 1 TPM auto-unlock; passphrase keyslot stays as the break-glass fallback.
  boot.initrd.luks.devices.crypted = {
    device = "/dev/disk/by-partlabel/luks";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
