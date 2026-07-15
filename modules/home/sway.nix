{
  aspects.homeManager.sway =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        libnotify
      ];

      wayland.windowManager.sway = {
        enable = true;
        xwayland = true;
        extraConfig = ''
          output eDP-1 scale 1
          output DP-6 scale 1
        '';
        config = rec {
          modifier = "Mod4";
          terminal = "ghostty";
          input = {
            "*" = {
              xkb_layout = "pl";
              repeat_delay = "250";
              repeat_rate = "50";
            };
          };
          # DMS owns the regular clipboard and its rich MIME types. PRIMARY
          # remains compositor/application-owned for middle-click pasting.
          startup = [ ];
          bars = [ ];
          for_window."app_id == \"swappy\"" = "floating enable";
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
            "${modifier}+Shift+Left" = "move workspace to output left";
            "${modifier}+Shift+Right" = "move workspace to output right";
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
            "${modifier}+space" = "exec dms ipc call spotlight toggle";
            "${modifier}+Ctrl+space" = "focus mode_toggle";
            "${modifier}+Shift+minus" = "move scratchpad";
            "${modifier}+minus" = "scratchpad show";
            "${modifier}+m" = "move scratchpad";
            "${modifier}+e" = "exec dms ipc call spotlight toggleQuery \":e\"";
            "${modifier}+f" = "fullscreen toggle";
            "Ctrl+${modifier}+l" = "exec dms ipc call lock lock";
            "${modifier}+Tab" = "workspace next";
            "${modifier}+Shift+Tab" = "workspace prev";
            "${modifier}+x" = "exec dms ipc call powermenu toggle";
            "${modifier}+n" = "exec dms ipc call notifications toggle";
            "${modifier}+v" = "exec dms ipc call clipboard toggle";
            "Ctrl+Print" =
              "exec bash -c 'f=~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png && mkdir -p \"$(dirname \"$f\")\" && grim - | swappy -f - -o \"$f\" && notify-send \"Screenshot saved: $f\"'";
            "${modifier}+Ctrl+Shift+3" =
              "exec bash -c 'f=~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png && mkdir -p \"$(dirname \"$f\")\" && grim - | swappy -f - -o \"$f\" && notify-send \"Screenshot saved: $f\"'";
            "${modifier}+Ctrl+Shift+4" =
              "exec bash -c 'f=~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png && mkdir -p \"$(dirname \"$f\")\" && grim -g \"$(slurp)\" - | swappy -f - -o \"$f\" && notify-send \"Screenshot saved: $f\"'";
            "XF86AudioRaiseVolume" = "exec dms ipc call audio increment 3";
            "XF86AudioLowerVolume" = "exec dms ipc call audio decrement 3";
            "XF86AudioMute" = "exec dms ipc call audio mute";
            "XF86AudioMicMute" = "exec dms ipc call audio micmute";
            "XF86MonBrightnessUp" = "exec dms ipc call brightness increment 5";
            "XF86MonBrightnessDown" = "exec dms ipc call brightness decrement 5";
          };
        };
      };

      programs = {
        ghostty = {
          enable = true;
          enableZshIntegration = true;
          settings = {
            font-family = "JetBrainsMono Nerd Font";
            font-size = 13;
            background-opacity = 0.95;
            confirm-close-surface = false;
            copy-on-select = "clipboard";
            window-decoration = "auto";
          };
        };

        dank-material-shell = {
          enable = true;
          systemd.enable = true;
          enableSystemMonitoring = true;
          enableDynamicTheming = true;
          enableVPN = false;
          enableCalendarEvents = false;
          settings = builtins.fromJSON (builtins.readFile ./dms-settings.json);
          clipboardSettings = {
            disabled = false;
            maxHistory = 100;
            maxPinned = 25;
            maxEntrySize = 5 * 1024 * 1024;
            autoClearDays = 7;
            clearAtStartup = false;
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

      # Bitwarden writes secrets to the regular clipboard. Keep a text-only
      # copy in PRIMARY so middle-click paste works too; a one-way bridge
      # avoids feedback loops and does not reinterpret image/file offers.
      systemd.user.services.clipboard-primary-sync = {
        Unit = {
          Description = "Copy regular clipboard text to PRIMARY";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.wl-clipboard}/bin/wl-copy --primary";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      gtk = {
        enable = true;
        theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
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
