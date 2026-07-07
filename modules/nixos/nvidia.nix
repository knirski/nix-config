{
  aspects.nixos.nvidia =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.workstation.nvidiaConfig;
    in
    {
      options.workstation.nvidiaConfig = {
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
            "sync"
            "offload"
          ];
          default = "sync";
          description = ''
            PRIME mode:
            - sync: NVIDIA renders everything, frames copied to Intel. Best for gaming.
            - offload: Intel renders by default, on-demand NVIDIA offload. Better battery life.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Must set videoDrivers to "nvidia" — hardware.nvidia.enabled is
        # read-only (computed from elem "nvidia" videoDrivers). Without this,
        # nouveau loads instead of the proprietary driver, killing GPU perf.
        services.xserver.videoDrivers = [ "nvidia" ];

        # Systemd resume hook to work around COSMIC compositor losing DRM
        # master on resume with dual Intel+NVIDIA GPUs in PRIME offload mode
        # (https://github.com/pop-os/cosmic-epoch/issues/3012). Switching VTs
        # forces logind to reassign DRM master so the compositor can render.
        systemd.services.force-drm-master-on-resume = {
          description = "Force DRM master reacquisition after resume (COSMIC dual-GPU workaround)";
          after = [ "post-resume.target" ];
          wants = [ "post-resume.target" ];
          wantedBy = [ "post-resume.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            TTY=$(cat /sys/class/tty/tty0/active)
            # Switch to a spare VT (tty8) and back to force DRM master handoff
            chvt 8 2>/dev/null
            sleep 0.5
            chvt "$TTY" 2>/dev/null
          '';
        };
        hardware = {
          # Latest NVIDIA driver (from nixpkgs-unstable)
          nvidia = {
            package = config.boot.kernelPackages.nvidiaPackages.latest;
            modesetting.enable = true;
            nvidiaSettings = true;
            powerManagement.enable = true;
            powerManagement.finegrained = true;
            open = false; # Proprietary driver (RTX 4000 Ada needs this)
            nvidiaPersistenced = true;
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
