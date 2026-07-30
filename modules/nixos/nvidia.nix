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
          # Stable production-branch NVIDIA driver (595.x series).  The open
          # kernel modules support Ada GPUs and are required for the modern
          # kernel suspend-notifier path used by NVIDIA 595+.
          nvidia = {
            package = config.boot.kernelPackages.nvidiaPackages.stable;
            modesetting.enable = true;
            nvidiaSettings = true;
            powerManagement = {
              enable = true;
              kernelSuspendNotifier = true;
              # finegrained = true enables per-engine power-gating, but
              # triggers an ABBA rw-semaphore deadlock in the ACPI notify
              # handler (rm_acpi_nvpcf_notify) when the NVIDIA driver receives
              # a USB-C dock hotplug ACPI event.  The nv_queue thread waits on
              # a mutex while ACPI kworkers pile up waiting for the same rwlock
              # — permanent wedge, requires cold power-cycle.
              # Keep finegrained = false while investigating the separate ACPI
              # dock-event deadlock seen with the proprietary path.
              finegrained = false;
            };
            open = true;
            # The old ZBook fix disabled GSP for the proprietary path; the
            # open kernel module needs GSP, so we keep it enabled here and use
            # the kernel suspend-notifier path instead.
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

      };
    };
}
