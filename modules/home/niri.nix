{
  aspects.homeManager.niri =
    { pkgs, ... }:
    let
      toggle-recording = pkgs.writeShellScriptBin "toggle-recording" ''
        if pgrep -x wf-recorder >/dev/null 2>&1; then
          pkill -x wf-recorder
          notify-send "Recording stopped" -t 2000
        else
          mkdir -p "$HOME/Videos/Screencasts"
          wf-recorder -f "$HOME/Videos/Screencasts/$(date +%Y-%m-%d_%H-%M-%S).mp4" \
            -c libx264 &>/dev/null &
          notify-send "Recording started" -t 2000
        fi
      '';
    in
    {
      # ── Niri compositor KDL config ─────────────────────────────────
      # Based on the official default-config.kdl from upstream.
      # https://github.com/YaLTeR/niri/blob/main/resources/default-config.kdl
      xdg.configFile."niri/config.kdl".text = ''
        // ── Input ────────────────────────────────────────────────────
        input {
            keyboard {
                xkb {
                    layout "us"
                }
                repeat-delay 600
                repeat-rate 25
            }
            touchpad {
                tap
                natural-scroll
                click-method "clickfinger"
            }
            warp-mouse-to-focus
            workspace-auto-back-and-forth
            focus-follows-mouse
        }

        // ── Layout ────────────────────────────────────────────────────
        layout {
            gaps 12

            focus-ring {
                width 3
                active-color "#cba6f7"
            }

            border {
                off
            }

            default-column-width { proportion 0.5 }
            center-focused-column "always"
            always-center-single-column
        }

        // ── Cursor ───────────────────────────────────────────────────
        cursor {
            xcursor-theme "catppuccin-mocha-mauve-cursors"
            xcursor-size 24
            hide-when-typing
        }

        // ── Screenshots ──────────────────────────────────────────────
        screenshot-path "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png"

        // ── Environment ──────────────────────────────────────────────
        environment {
            QT_QPA_PLATFORM "wayland;xcb"
            QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
        }

        // ── Binds ────────────────────────────────────────────────────
        binds {
            // Application launchers
            mod+Return { spawn "kitty"; }
            mod+D { spawn "fuzzel"; }

            // Close window
            mod+Q { close-window; }

            // Lock screen
            mod+Escape { spawn "swaylock"; }

            // Toggle window floating
            mod+Space { toggle-window-floating; }

            // Focus movement
            mod+H { focus-column-left; }
            mod+J { focus-window-down; }
            mod+K { focus-window-up; }
            mod+L { focus-column-right; }

            // Move windows
            mod+SHIFT+H { move-column-left; }
            mod+SHIFT+J { move-window-down; }
            mod+SHIFT+K { move-window-up; }
            mod+SHIFT+L { move-column-right; }

            // Workspace switching
            mod+1 { focus-workspace 1; }
            mod+2 { focus-workspace 2; }
            mod+3 { focus-workspace 3; }
            mod+4 { focus-workspace 4; }
            mod+5 { focus-workspace 5; }
            mod+6 { focus-workspace 6; }
            mod+7 { focus-workspace 7; }
            mod+8 { focus-workspace 8; }
            mod+9 { focus-workspace 9; }
            mod+0 { focus-workspace 10; }

            // Move windows to workspaces
            mod+SHIFT+1 { move-window-to-workspace 1; }
            mod+SHIFT+2 { move-window-to-workspace 2; }
            mod+SHIFT+3 { move-window-to-workspace 3; }
            mod+SHIFT+4 { move-window-to-workspace 4; }
            mod+SHIFT+5 { move-window-to-workspace 5; }
            mod+SHIFT+6 { move-window-to-workspace 6; }
            mod+SHIFT+7 { move-window-to-workspace 7; }
            mod+SHIFT+8 { move-window-to-workspace 8; }
            mod+SHIFT+9 { move-window-to-workspace 9; }
            mod+SHIFT+0 { move-window-to-workspace 10; }

            // Special workspace (scratchpad)
            mod+comma { toggle-window-floating; }
            mod+period { focus-workspace-previous; }

            // Consume / expel window from column
            mod+minus { consume-window-into-column; }
            mod+SHIFT+minus { expel-window-from-column; }

            // Screenshots
            Print { spawn "grimblast" "copysave" "area"; }
            mod+Print { spawn "grimblast" "copysave" "output"; }
            CTRL+Print { spawn "grimblast" "copysave" "area"; }

            // Overview
            mod+O { overview; }

            // Audio (repeating, allowed when locked)
            XF86AudioRaiseVolume { spawn "swayosd-client" "--output-volume" "+5"; allow-when-locked true; repeat; }
            XF86AudioLowerVolume { spawn "swayosd-client" "--output-volume" "-5"; allow-when-locked true; repeat; }
            XF86AudioMute { spawn "swayosd-client" "--output-volume" "mute-toggle"; allow-when-locked true; }

            // Media keys
            XF86AudioPlay { spawn "playerctl" "play-pause"; }
            XF86AudioNext { spawn "playerctl" "next"; }
            XF86AudioPrev { spawn "playerctl" "previous"; }

            // Brightness
            XF86MonBrightnessUp { spawn "brightnessctl" "s" "+5%"; repeat; }
            XF86MonBrightnessDown { spawn "brightnessctl" "s" "5%-"; repeat; }

            // Clipboard / emoji / recording
            mod+V { spawn "sh" "-c" "cliphist list | wofi --dmenu -p 'Clipboard' | cliphist decode | wl-copy"; }
            mod+E { spawn "emote"; }
            mod+SHIFT+R { spawn "toggle-recording"; }
            mod+CTRL+C { spawn "wl-color-picker"; }

            // Window drag/resize with mouse
            mod+mouse:272 { drag-window; }
            mod+mouse:273 { resize-window; }
        }

        // ── Spawn at startup ─────────────────────────────────────────
        spawn-at-startup "waybar"
        spawn-at-startup "swaybg" "-c" "#1e1e2e"
        spawn-at-startup "nm-applet" "--indicator"
        spawn-at-startup "blueman-applet"
        spawn-at-startup "wl-paste" "--watch" "cliphist" "store"
        spawn-at-startup "swayosd-server"
        spawn-at-startup "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"

        // ── Window rules ─────────────────────────────────────────────
        window-rule {
            match app-id "nm-connection-editor"
            open-floating
        }
        window-rule {
            match app-id "blueman-manager"
            open-floating
        }
        window-rule {
            match title "Authentication Required"
            open-floating
        }
        window-rule {
            match title "Picture-in-Picture"
            open-floating
        }
      '';

      # ── Tooling via HM modules ────────────────────────────────────

      programs = {
        swaylock = {
          enable = true;
          settings = {
            font-size = 24;
            show-failed-attempts = true;
            line-uses-ring = false;
            ring-color = "cba6f7";
            inside-clear-color = "a6e3a1";
            inside-ver-color = "89b4fa";
            inside-wrong-color = "f38ba8";
            key-hl-color = "cba6f7";
            bs-hl-color = "f38ba8";
            separator-color = "00000000";
            grace = 5;
            ignore-empty-password = false;
          };
        };

        waybar = {
          enable = true;
          settings = {
            mainBar = {
              layer = "top";
              position = "top";
              height = 30;
              modules-left = [ "niri/workspaces" ];
              modules-center = [ "clock" ];
              modules-right = [
                "pulseaudio"
                "network"
                "battery"
                "tray"
              ];

              "niri/workspaces" = { };
              clock = {
                format = "{:%H:%M}";
                tooltip-format = "{:%Y-%m-%d}";
              };
              pulseaudio = {
                format = "{icon} {volume}%";
                format-icons = [
                  "🔇"
                  "🔈"
                  "🔉"
                  "🔊"
                ];
                on-click = "pavucontrol";
              };
              network = {
                format-wifi = "{essid} ({signalStrength}%)";
                format-ethernet = "🖧";
                format-disconnected = "⚠ Disconnected";
                tooltip-format = "{ifname} via {gwaddr}";
              };
              battery = {
                format = "{icon} {capacity}%";
                format-icons = [
                  "🔋"
                  "🔋"
                  "🔋"
                  "🔋"
                  "🔋"
                ];
                format-charging = "⚡{capacity}%";
              };
              tray = { };
            };
          };
          style = ''
            * {
              font-family: "JetBrainsMono Nerd Font";
              font-size: 13px;
              min-height: 0;
            }
            window#waybar {
              background: rgba(30, 30, 46, 0.85);
              color: #cdd6f4;
            }
            #workspaces button {
              padding: 0 6px;
              color: #585b70;
            }
            #workspaces button.active {
              color: #cba6f7;
            }
            #clock, #pulseaudio, #network, #battery, #tray {
              padding: 0 10px;
              color: #cdd6f4;
            }
          '';
        };

        fuzzel = {
          enable = true;
          settings = {
            main = {
              terminal = "kitty";
              font = "JetBrainsMono Nerd Font:size=13";
              dpi-aware = "no";
              icons-enabled = "yes";
            };
            colors = {
              background = "1e1e2edd";
              text = "cdd6f4";
              match = "cba6f7";
              selection = "313244";
              selection-text = "cdd6f4";
              border = "cba6f7";
            };
            border = {
              radius = 8;
            };
          };
        };
      };

      services = {
        swayidle = {
          enable = true;
          timeouts = [
            {
              timeout = 300;
              command = "${pkgs.swaylock}/bin/swaylock -f";
            }
            {
              timeout = 600;
              command = "systemctl suspend";
            }
          ];
          events = {
            before-sleep = "${pkgs.swaylock}/bin/swaylock -f";
            lock = "${pkgs.swaylock}/bin/swaylock -f";
          };
        };

        wlsunset = {
          enable = true;
          latitude = 52.0;
          longitude = 21.0;
          temperature = {
            day = 6500;
            night = 3500;
          };
        };

        mako = {
          enable = true;
          settings = {
            anchor = "top-right";
            border-size = 2;
            border-color = "#cba6f7";
            background-color = "#1e1e2e";
            text-color = "#cdd6f4";
            width = 350;
            height = 200;
            padding = "12";
            default-timeout = 5000;
            font = "JetBrainsMono Nerd Font 12";
          };
        };
      };

      home.packages = with pkgs; [
        # Image / script tools kept from Hyprland
        wl-clipboard
        cliphist
        swayosd
        wofi
        emote
        wf-recorder
        toggle-recording
        libnotify
        playerctl
        brightnessctl
        networkmanagerapplet

        # Niri-specific replacements
        grimblast
        wl-color-picker
        swaybg # wallpaper (spawned in KDL config)
        polkit_gnome
        pavucontrol
      ];
    };
}
