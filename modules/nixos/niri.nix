{
  aspects.nixos.niri =
    { pkgs, ... }:
    {
      programs = {
        niri = {
          enable = true;
          # xwayland-satellite replaces XWayland for better isolation, but
          # requires unstable niri. Stick with xwayland for now.
          # useNautilus defaults to true (needed for xdg-desktop-portal-gnome).
        };
      };

      # Ly TUI greeter — auto-detects niri.desktop from sessionPackages.
      services.displayManager.ly.enable = true;

      # niri uses GNOME portals for screencast/screenshot (not wlr).
      # programs.niri already sets up xdg.portal.config.niri and installs
      # xdg-desktop-portal-gnome.

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
