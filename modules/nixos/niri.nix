{
  aspects.nixos.niri =
    { pkgs, ... }:
    {
      programs = {
        niri = {
          enable = true;
        };
      };

      # Sway alongside niri — user picks at Ly login.
      programs.sway = {
        enable = true;
        wrapperFeatures.gtk = true;
      };

      # Ly TUI greeter — auto-detects desktop files from sessionPackages.
      services.displayManager.ly.enable = true;

      # Portals: niri uses xdg-desktop-portal-gnome (handled by programs.niri).
      # Force dark theme for GNOME portal layer.
      programs.dconf.enable = true;

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        MOZ_ENABLE_WAYLAND = "1";
        QT_QPA_PLATFORM = "wayland;xcb";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        XDG_SESSION_TYPE = "wayland";
        XDG_CURRENT_DESKTOP = "niri";
      };

      environment.systemPackages = with pkgs; [
        libsForQt5.qt5ct
        qt6Packages.qt6ct
      ];

      qt = {
        platformTheme.name = "qtct";
        style = "adwaita";
      };
    };
}
