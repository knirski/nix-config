{
  aspects.homeManager.sway = { pkgs, ... }: {
    # ── Sway Window Manager ────────────────────────────────────────
    wayland.windowManager.sway = {
      enable = true;
      xwayland = true;
      config = rec {
        modifier = "Mod4";
        terminal = "kitty";
        startup = [ ];
        keybindings = {
          "${modifier}+Return" = "exec ${terminal}";
          "${modifier}+Q" = "kill";
          "${modifier}+h" = "focus left";
          "${modifier}+j" = "focus down";
          "${modifier}+k" = "focus up";
          "${modifier}+l" = "focus right";
          "${modifier}+Shift+h" = "move left";
          "${modifier}+Shift+j" = "move down";
          "${modifier}+Shift+k" = "move up";
          "${modifier}+Shift+l" = "move right";
          "${modifier}+1" = "workspace number 1";
          "${modifier}+2" = "workspace number 2";
          "${modifier}+3" = "workspace number 3";
          "${modifier}+4" = "workspace number 4";
          "${modifier}+5" = "workspace number 5";
          "${modifier}+6" = "workspace number 6";
          "${modifier}+7" = "workspace number 7";
          "${modifier}+8" = "workspace number 8";
          "${modifier}+9" = "workspace number 9";
          "${modifier}+Shift+1" = "move container to workspace number 1";
          "${modifier}+Shift+2" = "move container to workspace number 2";
          "${modifier}+Shift+3" = "move container to workspace number 3";
          "${modifier}+Shift+4" = "move container to workspace number 4";
          "${modifier}+Shift+5" = "move container to workspace number 5";
          "${modifier}+Shift+6" = "move container to workspace number 6";
          "${modifier}+Shift+7" = "move container to workspace number 7";
          "${modifier}+Shift+8" = "move container to workspace number 8";
          "${modifier}+Shift+9" = "move container to workspace number 9";
          "${modifier}+Shift+space" = "floating toggle";
          "${modifier}+space" = "focus mode_toggle";
          "${modifier}+Shift+minus" = "move scratchpad";
          "${modifier}+minus" = "scratchpad show";
          # ── DMS keybinds ─────────────────────────────────────
          "${modifier}+d" = "exec dms ipc call spotlight toggle";
          "${modifier}+Shift+d" = "exec dms ipc call lock lock";
          "${modifier}+x" = "exec dms ipc call powermenu toggle";
          "${modifier}+n" = "exec dms ipc call notifications toggle";
          "${modifier}+v" = "exec dms ipc call clipboard toggle";
          "${modifier}+comma" = "exec dms ipc call settings toggle";
          # ── Media keys ──────────────────────────────────────────
          "XF86AudioRaiseVolume" = "exec dms ipc call audio increment 3";
          "XF86AudioLowerVolume" = "exec dms ipc call audio decrement 3";
          "XF86AudioMute" = "exec dms ipc call audio mute";
          "XF86AudioMicMute" = "exec dms ipc call audio micmute";
          "XF86MonBrightnessUp" = "exec dms ipc call brightness increment 5";
          "XF86MonBrightnessDown" = "exec dms ipc call brightness decrement 5";
        };
      };
    };

    # ── Kitty terminal ─────────────────────────────────────────────
    programs.kitty = {
      enable = true;
      settings = {
        font_family = "JetBrainsMono Nerd Font";
        font_size = 13.0;
        background_opacity = "0.95";
        confirm_os_window_close = 0;
        shell = "/run/current-system/sw/bin/bash";
      };
    };

    # ── DMS: bar, launcher, notifications, OSD, lock, wallpaper, night light ──
    programs.dank-material-shell = {
      enable = true;
      systemd.enable = true;
      enableSystemMonitoring = true; # uses dgop
      enableVPN = false;
      enableDynamicTheming = true;
      enableAudioWavelength = true;
      enableCalendarEvents = false; # we use dcal instead

      settings = {
        # TODO: configure DMS settings per preference
        # See: https://danklinux.com/docs/dankmaterialshell/settings
      };
    };

    # ── Dark theme via dconf ───────────────────────────────────────
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };

    # ── Packages ───────────────────────────────────────────────────
    home.packages = with pkgs; [
      kitty
      # DMS replaces: wofi, cliphist, wl-clipboard, emote, libnotify,
      # playerctl, brightnessctl, networkmanagerapplet, pavucontrol,
      # grimblast (niri had built-in screenshots), wf-recorder/toggle-recording
    ];
  };
}
