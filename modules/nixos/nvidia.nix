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
