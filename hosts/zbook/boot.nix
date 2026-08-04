{ pkgs, ... }:
{
  boot = {
    # Follow the current kernel for newer graphics and suspend fixes on this
    # workstation; the NVIDIA package is selected from this kernel set too.
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "nvidia_drm.modeset=1"
      # ramoops/pstore: preserve panic, console, and ftrace logs across
      # unclean reboots. 1 MiB buffer at physical address 16 MiB — lowest
      # safe address in System RAM (above BIOS reservations at 1 MiB,
      # below the crash kernel at 608 MiB).
      "memmap=1M$16M"
      "ramoops.mem_address=0x01000000"
      "ramoops.mem_size=0x100000"
      "ramoops.console_size=0x10000"
      "ramoops.ftrace_size=0x10000"
      "ramoops.pmsg_size=0x10000"
      "ramoops.record_size=0x10000"
    ];
    crashDump = {
      enable = true;
      reservedMemory = "256M";
    };
    loader = {
      limine = {
        enable = true;
        secureBoot.enable = true;
        # Bound retained boot entries. Without this, every deploy adds a menu
        # entry and an ESP kernel/initrd copy that live forever, growing ESP
        # usage and boot-menu length without limit. This bounds Limine's menu,
        # not the Nix store: `nix.gc` (modules/nixos/maintenance.nix,
        # `--delete-older-than 30d`) reclaims store space separately, and the
        # persisted Secure Boot signing keys under /var/lib/sbctl are
        # untouched either way. See docs/update-and-rollback.md.
        maxGenerations = 10;
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
  services.hardware.bolt.enable = true;
}
