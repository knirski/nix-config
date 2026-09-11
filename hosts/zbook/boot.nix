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

  # Checked writeShellApplication (not writeShellScriptBin) with explicit
  # runtimeInputs: the shell-boundaries CI invariant rejects unchecked
  # helpers. Callees resolve through PATH from runtimeInputs, so the
  # store paths stay out of the script bodies.
  suspendDebugArm = pkgs.writeShellApplication {
    name = "suspend-debug-arm";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      if [ "''${EUID:-$(id -u)}" -ne 0 ]; then
        printf '%s\n' "Run this command as root from the suspend-debug boot." >&2
        exit 1
      fi

      trace=/sys/kernel/tracing
      pm_trace=/sys/power/pm_trace

      # Keep the trace focused on suspend ordering. These tracepoints are
      # low-volume, so they still hold the pre-hang history when khungtaskd
      # panics 120 s later; pstore's function recorder (record_ftrace) would
      # have been overwritten by other-CPU noise in the meantime. The
      # specialisation's panic_print=16 dumps this ring into the panic log,
      # which kmsg_dump then stores in ramoops.
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
    '';
  };

  suspendDebugSuspend = pkgs.writeShellApplication {
    name = "suspend-debug-suspend";
    runtimeInputs = [
      suspendDebugArm
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      suspend-debug-arm

      exec systemctl suspend
    '';
  };

  suspendDebugResyncTime = pkgs.writeShellApplication {
    name = "suspend-debug-resync-time";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.networkmanager
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      # Resume hooks race NetworkManager's link recovery. Wait for a usable
      # connection before restarting timesyncd; it will still retry if the link
      # is not ready within the bounded wait.
      nm-online --quiet --timeout=30 || true
      systemctl restart systemd-timesyncd.service
      sleep 2
    '';
  };
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
          # Preserve the laptop aspect's receiver reset and dock wake quirks;
          # mkForce replaces the merged kernel parameter list for this entry.
          "intel_pstate=active"
          "usbcore.quirks=046d:c52b:b,046d:c532:b,0bda:8153:j"
          "nvme_core.default_ps_max_latency_us=0"
          "pcie_aspm=off"
          # Preserve base/NixOS-generated parameters that mkForce would
          # otherwise replace, including crash diagnostics and boot behavior.
          "keyboard.delay=0"
          "keyboard.rate=50"
          "root=fstab"
          "loglevel=4"
          "lsm=landlock,yama,bpf"
          "crashkernel=256M"
          "nmi_watchdog=panic"
          "softlockup_panic=1"
          "no_console_suspend"
          # A silent s2idle-entry hang never reaches kmsg_dump, so ramoops
          # stays empty. Force blocking hangs to panic instead (see the
          # kernel.sysctl block below) and make the panic path write its
          # evidence *before* kdump takes over: kmsg_dump_desc stores the
          # console log in ramoops and panic_print's FTRACE_INFO bit appends
          # the power tracepoints to that same log. Without
          # crash_kexec_post_notifiers=1 the crash kernel runs first and both
          # records are never written.
          "crash_kexec_post_notifiers=1"
          # Print the suspend ordering to the framebuffer console while the
          # machine is still alive; the same messages stay in the kernel log
          # for the ramoops panic dump.
          "initcall_debug"
          "pm_debug_messages"
          "ignore_loglevel"
        ]
      );
      # Turn silent freezes into panics that kdump and ramoops can capture:
      # khungtaskd catches an uninterruptible (D-state) wait, while
      # panic_on_rcu_stall catches a CPU that stopped reporting. The
      # panic_print bit PANIC_PRINT_FTRACE_INFO (0x10) dumps the tracefs ring
      # into the panic log so the power tracepoints survive in ramoops.
      kernel.sysctl = {
        "kernel.hung_task_panic" = 1;
        "kernel.panic_on_rcu_stall" = 1;
        "kernel.panic_print" = 16;
      };
      # The crash/rescue kernel boots from the same kernel and initrd. Give it
      # the same ramoops reservation, otherwise it treats the reserved region
      # as free RAM and overwrites the evidence before it can be read. The
      # first two entries repeat boot.crashDump's defaults.
      crashDump.kernelParams = [
        "1"
        "boot.shell_on_fail"
      ]
      ++ debugRamoopsParams;
    };

    environment.systemPackages = [ suspendDebugSuspend ];

    # DMS/logind idle timeout, lid handling, and an explicit `systemctl
    # suspend` all converge on this unit. Arm diagnostics before the actual
    # transition without making systemd-suspend invoke the suspend helper
    # recursively.
    systemd.services.suspend-debug-arm = {
      description = "Arm suspend diagnostics before every debug suspend";
      before = [ "systemd-suspend.service" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${suspendDebugArm}/bin/suspend-debug-arm";
      };
    };

    # pm_trace deliberately perturbs the RTC while diagnosing suspend. Restart
    # timesyncd after the debug sleep operation returns so only this
    # specialisation repairs the wall clock.
    systemd.services.systemd-suspend.serviceConfig.ExecStartPost = [
      "${suspendDebugResyncTime}/bin/suspend-debug-resync-time"
    ];

  };

  zramSwap.enable = true;
  security.tpm2.enable = true;
  services.hardware.bolt.enable = true;
}
