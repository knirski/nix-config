{ lib, pkgs, ... }:
let
  commonKernelParams = [
    "nvidia_drm.modeset=1"
  ];

  normalRamoopsParams = [
    # Keep the existing normal-boot reservation unchanged. The debug
    # specialisation below replaces this with a larger region.
    "memmap=1M$16M"
    "ramoops.mem_address=0x01000000"
    "ramoops.mem_size=0x100000"
    "ramoops.console_size=0x10000"
    "ramoops.ftrace_size=0x10000"
    "ramoops.pmsg_size=0x10000"
    "ramoops.record_size=0x10000"
  ];

  debugRamoopsParams = [
    # The region is below the crashkernel reservation and large enough to
    # retain useful console/ftrace records across an unclean reboot.
    "memmap=8M$16M"
    "ramoops.mem_address=0x01000000"
    "ramoops.mem_size=0x800000"
    "ramoops.console_size=0x200000"
    "ramoops.ftrace_size=0x200000"
    "ramoops.pmsg_size=0x100000"
    "ramoops.record_size=0x100000"
  ];

  suspendDebugSuspend = pkgs.writeShellScriptBin "suspend-debug-suspend" ''
    set -euo pipefail

    if [ "''${EUID:-$(id -u)}" -ne 0 ]; then
      printf '%s\n' "Run this command with sudo from the suspend-debug boot." >&2
      exit 1
    fi

    trace=/sys/kernel/tracing
    pm_trace=/sys/power/pm_trace

    # Keep the trace focused on suspend ordering. PSTORE_FTRACE writes the
    # ftrace ring to ramoops if the kernel dies before it can resume.
    printf '%s\n' 0 > "$trace/tracing_on"
    printf '%s\n' nop > "$trace/current_tracer"
    : > "$trace/trace"
    printf '%s\n' power:suspend_resume > "$trace/set_event"
    printf '%s\n' power:device_pm_callback_start >> "$trace/set_event"
    printf '%s\n' power:device_pm_callback_end >> "$trace/set_event"
    printf '%s\n' 1 > "$trace/tracing_on"

    # pm_trace stores the last suspend/resume fingerprint in the RTC, so it
    # remains available after a cold reset. It also disables async suspend,
    # making this a deliberate diagnostic run rather than a normal cycle.
    printf '%s\n' 1 > "$pm_trace"

    exec ${pkgs.systemd}/bin/systemctl suspend
  '';
in
{
  boot = {
    # Follow the current kernel for newer graphics and suspend fixes on this
    # workstation; the NVIDIA package is selected from this kernel set too.
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = commonKernelParams ++ normalRamoopsParams;
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

  # Keep the expensive custom kernel and altered suspend behavior out of the
  # daily boot. Select this entry from Limine only for controlled experiments.
  specialisation.suspend-debug.configuration = {
    boot = {
      # These backends are disabled in the stock kernel config. A targeted
      # patch avoids changing the normal kernel while enabling ramoops to
      # retain console, pmsg, and ftrace data for this entry.
      kernelPatches = [
        {
          name = "suspend-debug-pstore";
          patch = null;
          extraConfig = ''
            PSTORE_CONSOLE y
            PSTORE_FTRACE y
            PSTORE_PMSG y
            # efi_pstore otherwise claims the single pstore backend before
            # ramoops is probed, leaving the reserved RAM region unused.
            EFI_VARS_PSTORE n
          '';
        }
      ];
      initrd.kernelModules = [ "ramoops" ];
      kernelParams = lib.mkForce (
        commonKernelParams
        ++ debugRamoopsParams
        ++ [
          "no_console_suspend"
        ]
      );
    };

    environment.systemPackages = [ suspendDebugSuspend ];
  };

  zramSwap.enable = true;
  security.tpm2.enable = true;
  services.hardware.bolt.enable = true;
}
