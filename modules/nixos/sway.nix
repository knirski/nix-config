{
  aspects.nixos.sway = _: {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    # DMS greetd greeter — identical look to the DMS lock screen.
    programs.dank-material-shell.greeter = {
      enable = true;
      compositor.name = "sway";
    };

    # DMS supplies the greetd preStart through its upstream module. The pinned
    # implementation currently triggers SC2155, SC2162, and SC2035; none of
    # that script is authored here. Keep the exception scoped to this unit.
    systemd.services.greetd.enableStrictShellChecks = false;

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland;xcb";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "sway";
      SWAY_UNSUPPORTED_GPU = "1";
    };
  };
}
