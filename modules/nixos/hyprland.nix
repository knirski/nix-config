{
  aspects.nixos.hyprland =
    { pkgs, ... }:
    {
      programs = {
        hyprland = {
          enable = true;
          xwayland.enable = true;
        };
      };

      services = {
        greetd = {
          enable = true;
          settings = {
            default_session = {
              command = "${pkgs.gtkgreet}/bin/gtkgreet";
              user = "greeter";
            };
          };
        };

      };

      # Desktop portal for screen sharing / screenshot permissions
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
      };

      # Wayland environment for all apps (set system-wide so GTK/Qt/Electron
      # pick them up even before Hyprland's own env config applies)
      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1"; # Tell Electron/Chrome to use Wayland
        MOZ_ENABLE_WAYLAND = "1";
        QT_QPA_PLATFORM = "wayland;xcb";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        XDG_SESSION_TYPE = "wayland";
        XDG_CURRENT_DESKTOP = "Hyprland";
      };

      environment.systemPackages = with pkgs; [
        libsForQt5.qt5ct
        qt6Packages.qt6ct
      ];

      # Qt theming needs these to find Qt plugins
      qt = {
        platformTheme = "qtct";
        style = "adwaita";
      };
    };
}
