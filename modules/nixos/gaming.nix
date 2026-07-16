{
  aspects.nixos.gaming =
    { pkgs, ... }:
    {
      programs = {
        # Steam
        steam = {
          enable = true;
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
          gamescopeSession.enable = true;
          # Ensure games use the NVIDIA GPU in offload mode
          package = pkgs.steam.override {
            extraEnv = {
              __NV_PRIME_RENDER_OFFLOAD = "1";
              __GLX_VENDOR_LIBRARY_NAME = "nvidia";
              __VK_LAYER_NV_optimus = "NVIDIA_only";
            };
          };
        };

        # Gamemode — automatic game optimisation
        gamemode = {
          enable = true;
          settings = {
            general = {
              softrealtime = "off";
              reaper_freq = 5;
              defaultgov = "performance";
              desiredgov = "performance";
            };
          };
        };

        # Gamescope — gaming-oriented compositor
        gamescope.enable = true;
      };

      # Gaming tools
      environment.systemPackages = with pkgs; [
        mangohud # Overlay for FPS, temps, etc.
        goverlay # GUI for mangohud
        protonup-qt # Proton GE manager
        lutris # Game launcher
        (pkgs.symlinkJoin {
          name = "heroic-launcher-nvidia";
          paths = [ pkgs.heroic-launcher ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/heroic \
              --set __NV_PRIME_RENDER_OFFLOAD "1" \
              --set __GLX_VENDOR_LIBRARY_NAME "nvidia" \
              --set __VK_LAYER_NV_optimus "NVIDIA_only"
          '';
        })
      ];

      # Wine/proton support requires 32-bit GL
      hardware.graphics.enable32Bit = true;
    };
}
