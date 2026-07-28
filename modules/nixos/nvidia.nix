{
  aspects.nixos.nvidia =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.lanAppliance.services.nvidia;
    in
    {
      options.lanAppliance.services.nvidia = {
        enable = lib.mkEnableOption "NVIDIA GPU support with Optimus PRIME";
        prime = {
          intelBusId = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Bus ID for the Intel GPU, e.g. PCI:0:2:0";
          };
          nvidiaBusId = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Bus ID for the NVIDIA GPU, e.g. PCI:1:0:0";
          };
        };
        syncMode = lib.mkOption {
          type = lib.types.enum [
            "offload"
            "sync"
          ];
          default = "offload";
          description = ''
            PRIME mode:
            - offload: Intel renders by default, on-demand NVIDIA offload. Better battery life.
            - sync: NVIDIA renders everything, frames copied to Intel. Best for gaming.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Must set videoDrivers to "nvidia" — hardware.nvidia.enabled is
        # read-only (computed from elem "nvidia" videoDrivers). Without this,
        # nouveau loads instead of the proprietary driver, killing GPU perf.
        services.xserver.videoDrivers = [ "nvidia" ];

        hardware = {
          # Stable production-branch NVIDIA driver (595.x series).  Both
          # 595.x and 610.x have an ABBA rw-semaphore deadlock in
          # rm_acpi_nvpcf_notify (the ACPI handler for USB-C dock events)
          # that permanently wedges the GPU and requires a cold power-cycle.
          nvidia = {
            package = config.boot.kernelPackages.nvidiaPackages.stable;
            modesetting.enable = true;
            nvidiaSettings = true;
            powerManagement.enable = true;
            # finegrained = true enables per-engine power-gating, but
            # triggers an ABBA rw-semaphore deadlock in the ACPI notify
            # handler (rm_acpi_nvpcf_notify) when the NVIDIA driver receives
            # a USB-C dock hotplug ACPI event.  The nv_queue thread waits on
            # a mutex while ACPI kworkers pile up waiting for the same rwlock
            # — permanent wedge, requires cold power-cycle.
            # Confirmed on both 595.x (stable) and 610.x (new feature).
            # Keep finegrained = false as a blanket workaround.
            powerManagement.finegrained = false;
            open = false; # Proprietary driver (RTX 4000 Ada needs this)
            # In offload mode the GPU powers down — persistenced isn't needed
            # and just fails trying to query the sleeping device.
            nvidiaPersistenced = false;
            prime = {
              inherit (cfg.prime) intelBusId nvidiaBusId;
              sync.enable = cfg.syncMode == "sync";
              offload = {
                enable = cfg.syncMode == "offload";
                enableOffloadCmd = cfg.syncMode == "offload";
              };
            };
          };

          # OpenGL (both 64 and 32-bit for gaming)
          graphics = {
            enable = true;
            enable32Bit = true;
          };
        };

        # Disable NVIDIA's GSP (GPU System Processor) firmware. The proprietary
        # RISC-V firmware blobs shipped across 570→610+ have a known bug where
        # the GSP crashes (Xid 120) during s2idle resume, permanently wedging
        # /proc/driver/nvidia/suspend and preventing any future suspend.
        # The kernel module handles GPU init and power management fine without
        # it — negligible perf impact on RTX 4000 Ada.
        # Ref: https://wiki.archlinux.org/title/NVIDIA/Troubleshooting#Disable_the_GSP_firmware
        boot.extraModprobeConfig = "options nvidia NVreg_EnableGpuFirmware=0";

        # systemd v256+ freezes cgroups before suspend by default. On NVIDIA
        # Optimus systems, the 60s user.slice freeze timeout races with
        # nvidia-suspend — if certain processes (Docker, libvirtd, Electron
        # apps) refuse to freeze, the delay can corrupt GPU state and leave
        # the graphical session unusable after resume.
        # Skip the freeze and let NVIDIA's own suspend handle sequencing.
        # https://github.com/NixOS/nixpkgs/issues/371058
        systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";

        # If nvidia-suspend hangs (as seen with rw-semaphore contention in
        # driver 610.43.03), kill it after 10s so the suspend aborts cleanly.
        # Normal completes take <2s.
        systemd.services.nvidia-suspend.serviceConfig = {
          TimeoutSec = 10;
          # mixed: SIGTERM main process, then SIGKILL remaining cgroup
          # processes after timeout. Explicit is safer than relying on
          # the default (control-group) for a stuck kernel-thread hang.
          KillMode = "mixed";
        };
      };
    };
}
