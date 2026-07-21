{
  aspects.nixos.sway = { pkgs, lib, ... }: {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    # Cursor theme for Wayland clients. Sets both the Sway seat defaults
    # and the GTK cursor theme so all toolkits (GTK, Qt, Electron via
    # XCURSOR_THEME) use the same cursor set.
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      polkit_gnome
      ddcutil
    ];

    # DDC/CI monitor control (input source switching, brightness, etc.)
    # hardware.i2c loads the i2c-dev kernel module and sets up udev rules
    # so users in the `i2c` group can access I2C buses without root.
    # The user is added to the `i2c` group in the host-level users.nix.
    hardware.i2c.enable = true;

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

    # DMS greetd greeter (from the dank-greeter repo) — identical look to
    # the DMS lock screen. The greeter runs before the user logs in as the
    # system `greeter` user. Without access to /dev/dri devices, Sway falls
    # back to software rendering (Pixman/llvmpipe), which is too slow for the
    # animated DMS greeter — choppy/framey UI is the symptom.
    programs.dms-greeter = {
      enable = true;
      compositor.name = "sway";
    };
    users.users.greeter.extraGroups = [
      "video"
      "render"
    ];

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
      XCURSOR_THEME = "Adwaita";
      XCURSOR_SIZE = "24";
      SWAY_UNSUPPORTED_GPU = "1";

      # Force software cursors on NVIDIA.  The proprietary driver's hardware
      # cursor plane is unreliable under wlroots — software cursors are
      # smoother and avoid judder/stutter.  Same fix commonly applied for
      # Hyprland on NVIDIA (see AGENTS.md).
      WLR_NO_HARDWARE_CURSORS = "1";
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
