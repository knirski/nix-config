{
  aspects.homeManager.sway = _: {
    wayland.windowManager.sway = {
      enable = true;
      xwayland = true;
      # Use Sway's built-in default config for all standard binds.
      # Only define our overrides via extraConfig.
      config = null;
      extraConfig = ''
        set $mod Mod4
        set $term kitty
        # DMS IPC binds
        bindsym $mod+d exec dms ipc call spotlight toggle
        bindsym $mod+Shift+d exec dms ipc call lock lock
        bindsym $mod+x exec dms ipc call powermenu toggle
        bindsym $mod+n exec dms ipc call notifications toggle
        bindsym $mod+v exec dms ipc call clipboard toggle
        # Media / HID keys
        bindsym XF86AudioRaiseVolume exec dms ipc call audio increment 3
        bindsym XF86AudioLowerVolume exec dms ipc call audio decrement 3
        bindsym XF86AudioMute exec dms ipc call audio mute
        bindsym XF86AudioMicMute exec dms ipc call audio micmute
        bindsym XF86MonBrightnessUp exec dms ipc call brightness increment 5
        bindsym XF86MonBrightnessDown exec dms ipc call brightness decrement 5
        # No status bar — DMS provides it
        bar {
          status_command false
        }
      '';
    };

    programs = {
      kitty = {
        enable = true;
        settings = {
          font_family = "JetBrainsMono Nerd Font";
          font_size = 13.0;
          background_opacity = "0.95";
          confirm_os_window_close = 0;
          shell = "/run/current-system/sw/bin/bash";
        };
      };

      dank-material-shell = {
        enable = true;
        systemd.enable = true;
        # Must-haves: dgop for system monitoring, matugen for theming
        enableSystemMonitoring = true;
        enableDynamicTheming = true;
        # Replace unwanted defaults
        enableVPN = false;
        enableCalendarEvents = false; # use dcal
        # User preferences over DMS defaults
        settings = {
          color.predefinedScheme = "catppuccin-mocha";
          bar.position = "bottom";
        };
        plugins = {
          dankActions.enable = true;
          dankBatteryAlerts.enable = true;
          calculator.enable = true;
          emojiLauncher.enable = true;
        };
      };

      dank-calendar = {
        enable = true;
        systemd.enable = true;
      };
    };

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
      };
    };
  };
}
