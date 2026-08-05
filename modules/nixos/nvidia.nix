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
        disableGsp = lib.mkEnableOption "disable NVIDIA GSP firmware";
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
          # Latest supported NVIDIA driver branch from nixpkgs.  Use the
          # proprietary module because the ArchWiki GSP workaround is not
          # available with nvidia-open, and this ZBook has already hit an Xid
          # 120 GSP crash during power management.
          nvidia = {
            package = config.boot.kernelPackages.nvidiaPackages.latest;
            modesetting.enable = true;
            nvidiaSettings = true;
            # Keep the workaround in nixpkgs' typed interface so it merges
            # with the module's own parameters and is rendered into the
            # generated modprobe configuration.
            gsp.enable = lib.mkIf cfg.disableGsp false;
            moduleParams = lib.optionalAttrs cfg.disableGsp {
              nvidia.NVreg_EnableGpuFirmware = 0;
            };
            powerManagement = {
              enable = true;
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
            open = false;
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
