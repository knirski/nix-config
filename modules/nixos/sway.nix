{
  aspects.nixos.sway = { pkgs, lib, ... }: {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    # Polkit authentication agent for GUI privilege escalation
    security.polkit.enable = true;
    environment.systemPackages = with pkgs; [
      polkit_gnome
    ];
    systemd.user.services.polkit-gnome-authentication-agent = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
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
      XDG_CURRENT_PORTAL = "wlr";
      SWAY_UNSUPPORTED_GPU = "1";
    };

    # XDG Desktop Portals for Wayland
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      # nixpkgs sway module sets config.sway.default = "gtk";
      # mkForce to keep our wlr+gtk preference instead.
      config.sway.default = lib.mkForce "wlr;gtk";
    };
  };
}
