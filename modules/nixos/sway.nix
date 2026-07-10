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
