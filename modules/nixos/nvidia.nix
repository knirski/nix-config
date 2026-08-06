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
        disableFineGrainedPm = lib.mkEnableOption ''
          cap NVreg_DynamicPowerManagement at 0x01 (dynamic PM without
          fine-grained power gating), working around the rm_acpi_nvpcf_notify
          ABBA deadlock.  ZBook-specific; set from the host data file.
        '';
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
            # Express the GSP workaround through nixpkgs' typed option so it
            # merges into the generated modprobe configuration.
            gsp.enable = lib.mkIf cfg.disableGsp false;
            moduleParams = {
              nvidia =
                lib.optionalAttrs cfg.disableGsp {
                  NVreg_EnableGpuFirmware = 0;
                }
                // lib.optionalAttrs cfg.disableFineGrainedPm {
                  # finegrained = false alone is a no-op: nixpkgs only emits
                  # NVreg_DynamicPowerManagement when finegrained = true, so
                  # the driver default (0x03 = dynamic + fine-grained) applies
                  # and the deadlock persists.  Render the explicit 0x01
                  # (dynamic PM, no fine-grained power gating) instead.
                  # `//` merges shallowly — both sides define `nvidia`.
                  NVreg_DynamicPowerManagement = "0x01";
                };
            };
            powerManagement = {
              enable = true;
              # finegrained = true enables per-engine power-gating, which
              # triggers the rm_acpi_nvpcf_notify ABBA deadlock (USB-C dock
              # hotplug ACPI event): nv_queue waits on a mutex while ACPI
              # kworkers pile up on the same rwlock — permanent wedge, cold
              # power-cycle only.  Keep it off; disableFineGrainedPm is the
              # real kill switch (see moduleParams above).
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
