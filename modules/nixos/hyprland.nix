{
  aspects.nixos.hyprland =
    { pkgs, ... }:
    {
      programs = {
        hyprland = {
          enable = true;
          xwayland.enable = true;
          withUWSM = true;
        };
      };

      # Ly is a modern Rust TUI greeter with mouse support and themes.
      # No compositor dependencies — runs on the raw VT. Auto-detects
      # the hyprland-uwsm.desktop installed by programs.hyprland.
      services.displayManager.ly.enable = true;

      # Desktop portal for screen sharing / screenshot permissions
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
      };

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        MOZ_ENABLE_WAYLAND = "1";
        QT_QPA_PLATFORM = "wayland;xcb";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        XDG_SESSION_TYPE = "wayland";
        XDG_CURRENT_DESKTOP = "Hyprland";
      };

      environment.systemPackages = with pkgs; [
        uwsm
        libsForQt5.qt5ct
        qt6Packages.qt6ct
      ];

      qt = {
        platformTheme.name = "qtct";
        style = "adwaita";
      };
    };
}
