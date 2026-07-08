{ pkgs, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      limine = {
        enable = true;
        # Temporarily disabled: sbctl keys were lost from /persist/var/lib/sbctl.
        # Re-enable after recreating keys (see docs/recovery.md).
        secureBoot.enable = false;
      };
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

  # systemd-boot-random-seed writes to /boot/loader/random-seed on the ESP.
  # Since the ESP is vfat (no permissions), bootctl warns "world accessible"
  # every boot. This service only applies to systemd-boot; with Limine we
  # don't need it.
  systemd.services.systemd-boot-random-seed.enable = false;

  # Keep TPM unlock enabled in crypttab. After Secure Boot key enrollment,
  # re-enroll the TPM keyslot against PCR 0+2+7 (see docs/recovery.md).
  # The passphrase keyslot stays as the break-glass fallback.
}
