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
        # apps) refuse to freeze, the delay corrupts GPU state and leaves
        # cosmic-comp SIGSTOP'd after resume, requiring a cold reboot.
        # Skip the freeze and let NVIDIA's own suspend handle sequencing.
        # https://github.com/NixOS/nixpkgs/issues/371058
        systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
      };
    };
}
