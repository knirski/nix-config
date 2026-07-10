{
  aspects.nixos.sway =
    { pkgs, ... }:
    {
      programs = {
        sway = {
          enable = true;
          wrapperFeatures.gtk = true;
        };

        # DMS greetd-based greeter (replaces Ly). Looks identical to the DMS lock screen.
        dank-material-shell.greeter = {
          enable = true;
          compositor.name = "sway";
        };

        # DMS NixOS module enables power-profiles-daemon, accounts-daemon, geoclue2, polkit.
        dank-material-shell.enable = true;

        dconf.enable = true;
      };

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        MOZ_ENABLE_WAYLAND = "1";
        QT_QPA_PLATFORM = "wayland;xcb";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        XDG_SESSION_TYPE = "wayland";
        XDG_CURRENT_DESKTOP = "sway";
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
