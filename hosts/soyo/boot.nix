{ pkgs, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      limine = {
        enable = true;
        secureBoot.enable = true;
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

  # Blacklist i915 on this headless server. No display is attached, so loading
  # the GPU driver is pointless and triggers harmless but noisy kernel WARN_ON
  # backtraces (adlp_tc_phy_connect on Alder Lake N). This is host-specific:
  # other headless servers may need i915 for hardware transcoding (VA-API).
  boot.blacklistedKernelModules = [ "i915" ];

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
