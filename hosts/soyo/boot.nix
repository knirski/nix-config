{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap.enable = true;
  security.tpm2.enable = true;

  # Silence i915 TC port polling noise.  The Alder Lake-N iGPU driver
  # probes the Type-C controller for DisplayPort, but this headless N150
  # board has no physical DP-out.  The firmware reports TC_PORT_LEGACY
  # which the driver doesn't expect, producing a WARN backtrace every
  # ~25 seconds.  Harmless, but clutters the kernel log.
  boot.kernelParams = [ "i915.enable_tc=0" ];

  boot.loader.limine.enable = true;
  # Secure Boot disabled temporarily — enable after sbctl key enrollment:
  #   ssh krzysiek@soyo 'sudo sbctl create-keys && sudo sbctl enroll-keys -m'
  # boot.loader.limine.secureBoot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [
    "tpm_crb"
    "nvme"
    "xhci_pci"
    "uas"
    "sd_mod"
  ];

  # Phase 2: Limine Secure Boot is on (the module force-enables safe settings:
  # enrollConfig, validateChecksums, panicOnChecksumMismatch). Re-enroll the
  # TPM keyslot against PCR 0+2+7 after sbctl key enrollment (see docs/recovery.md).
  # Passphrase keyslot stays as the break-glass fallback.
  boot.initrd.luks.devices.crypted = {
    device = "/dev/disk/by-partlabel/luks";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
