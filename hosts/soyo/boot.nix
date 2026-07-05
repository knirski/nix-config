{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap.enable = true;
  security.tpm2.enable = true;

  boot.loader.limine.enable = true;
  # systemd-boot-random-seed writes to /boot/loader/random-seed on the ESP.
  # Since the ESP is vfat (no permissions), bootctl warns "world accessible"
  # every boot. This service only applies to systemd-boot; with Limine we
  # don't need it.
  systemd.services.systemd-boot-random-seed.enable = false;
  # Phase 2: enable Limine's Secure Boot mode declaratively first, then perform
  # the one-time firmware + sbctl key enrollment from docs/recovery.md.
  # The module force-enables the safe settings needed for a locked boot path.
  boot.loader.limine.secureBoot.enable = true;
  # Required during Secure Boot key enrollment (sbctl).  Safe to set to false
  # after enrollment is complete — future updates use signed pre-enrolled certs.
  boot.loader.efi.canTouchEfiVariables = false;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [
    "tpm_crb"
    "nvme"
    "xhci_pci"
    "uas"
    "sd_mod"
  ];

  # Keep TPM unlock enabled in crypttab. After Secure Boot key enrollment,
  # re-enroll the TPM keyslot against PCR 0+2+7 (see docs/recovery.md).
  # The passphrase keyslot stays as the break-glass fallback.
  boot.initrd.luks.devices.crypted = {
    device = "/dev/disk/by-partlabel/luks";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
