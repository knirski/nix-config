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
        heroic-launcher # Epic/GOG games launcher
      ];

      # Wine/proton support requires 32-bit GL
      hardware.graphics.enable32Bit = true;
    };
}
