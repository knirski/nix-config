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
      programs = {
        niri.settings = {
          input = {
            keyboard = {
              xkb = {
                layout = "us";
              };
              repeat-delay = 600;
              repeat-rate = 25;
            };
            touchpad = {
              tap = true;
              natural-scroll = true;
              click-method = "clickfinger";
            };
            warp-mouse-to-focus.enable = true;
            workspace-auto-back-and-forth = true;
            focus-follows-mouse.enable = true;
          };

          layout = {
            gaps = 12;
            focus-ring = {
              enable = true;
              width = 3;
              active.color = "#cba6f7";
            };
            border.enable = false;
            default-column-width = {
              proportion = 0.5;
            };
            center-focused-column = "always";
            background-color = "#1e1e2e";
          };

          cursor = {
            theme = "catppuccin-mocha-mauve-cursors";
            size = 24;
            hide-when-typing = true;
          };

          screenshot-path = "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png";
          prefer-no-csd = true;

          environment = {
            QT_QPA_PLATFORM = "wayland;xcb";
            QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
          };

          binds = {
            "Mod+Return".action.spawn = [ "kitty" ];
            "Mod+Q".action = {
              close-window = [ ];
            };
            "Mod+Shift+Space".action = {
              toggle-window-floating = [ ];
            };
            "Mod+Shift+V".action = {
              switch-focus-between-floating-and-tiling = [ ];
            };

            "Mod+H".action = {
              focus-column-left = [ ];
            };
            "Mod+J".action = {
              focus-window-down = [ ];
            };
            "Mod+K".action = {
              focus-window-up = [ ];
            };
            "Mod+L".action = {
              focus-column-right = [ ];
            };
            "Mod+Home".action = {
              focus-column-first = [ ];
            };
            "Mod+End".action = {
              focus-column-last = [ ];
            };
            "Mod+Ctrl+H".action = {
              move-column-left = [ ];
            };
            "Mod+Ctrl+J".action = {
              move-window-down = [ ];
            };
            "Mod+Ctrl+K".action = {
              move-window-up = [ ];
            };
            "Mod+Ctrl+L".action = {
              move-column-right = [ ];
            };
            "Mod+Ctrl+Home".action = {
              move-column-to-first = [ ];
            };
            "Mod+Ctrl+End".action = {
              move-column-to-last = [ ];
            };
            "Mod+Shift+H".action = {
              focus-monitor-left = [ ];
            };
            "Mod+Shift+J".action = {
              focus-monitor-down = [ ];
            };
            "Mod+Shift+K".action = {
              focus-monitor-up = [ ];
            };
            "Mod+Shift+L".action = {
              focus-monitor-right = [ ];
            };
            "Mod+Shift+Ctrl+H".action = {
              move-column-to-monitor-left = [ ];
            };
            "Mod+Shift+Ctrl+J".action = {
              move-column-to-monitor-down = [ ];
            };
            "Mod+Shift+Ctrl+K".action = {
              move-column-to-monitor-up = [ ];
            };
            "Mod+Shift+Ctrl+L".action = {
              move-column-to-monitor-right = [ ];
            };
            "Mod+Alt+H".action = {
              move-workspace-to-monitor-left = [ ];
            };
            "Mod+Alt+J".action = {
              move-workspace-to-monitor-down = [ ];
            };
            "Mod+Alt+K".action = {
              move-workspace-to-monitor-up = [ ];
            };
            "Mod+Alt+L".action = {
              move-workspace-to-monitor-right = [ ];
            };

            "Mod+1".action.focus-workspace = 1;
            "Mod+2".action.focus-workspace = 2;
            "Mod+3".action.focus-workspace = 3;
            "Mod+4".action.focus-workspace = 4;
            "Mod+5".action.focus-workspace = 5;
            "Mod+6".action.focus-workspace = 6;
            "Mod+7".action.focus-workspace = 7;
            "Mod+8".action.focus-workspace = 8;
            "Mod+9".action.focus-workspace = 9;
            "Mod+0".action.focus-workspace = 10;
            "Mod+Ctrl+1".action.move-column-to-workspace = 1;
            "Mod+Ctrl+2".action.move-column-to-workspace = 2;
            "Mod+Ctrl+3".action.move-column-to-workspace = 3;
            "Mod+Ctrl+4".action.move-column-to-workspace = 4;
            "Mod+Ctrl+5".action.move-column-to-workspace = 5;
            "Mod+Ctrl+6".action.move-column-to-workspace = 6;
            "Mod+Ctrl+7".action.move-column-to-workspace = 7;
            "Mod+Ctrl+8".action.move-column-to-workspace = 8;
            "Mod+Ctrl+9".action.move-column-to-workspace = 9;

            "Mod+U".action = {
              focus-workspace-up = [ ];
            };
            "Mod+I".action = {
              focus-workspace-down = [ ];
            };
            "Mod+Tab".action = {
              focus-workspace-previous = [ ];
            };
            "Mod+Comma".action = {
              consume-window-into-column = [ ];
            };
            "Mod+Period".action = {
              expel-window-from-column = [ ];
            };

            "Mod+R".action = {
              switch-preset-column-width = [ ];
            };
            "Mod+Shift+R".action = {
              switch-preset-column-width-back = [ ];
            };
            "Mod+Alt+R".action = {
              reset-window-height = [ ];
            };
            "Mod+Minus".action.set-column-width = [ "-10%" ];
            "Mod+Equal".action.set-column-width = [ "+10%" ];
            "Mod+Shift+Minus".action.set-window-height = [ "-10%" ];
            "Mod+Shift+Equal".action.set-window-height = [ "+10%" ];

            "Mod+F".action = {
              maximize-column = [ ];
            };
            "Mod+Shift+F".action = {
              fullscreen-window = [ ];
            };
            "Mod+M".action = {
              maximize-window-to-edges = [ ];
            };
            "Mod+Ctrl+F".action = {
              expand-column-to-available-width = [ ];
            };
            "Mod+C".action = {
              center-column = [ ];
            };
            "Mod+Ctrl+C".action = {
              center-visible-columns = [ ];
            };
            "Mod+W".action = {
              toggle-column-tabbed-display = [ ];
            };
            "Mod+O".action = {
              toggle-overview = [ ];
            };

            "Print".action = {
              screenshot = [ ];
            };
            "Ctrl+Print".action = {
              screenshot-screen = [ ];
            };

            "Mod+Shift+Slash".action = {
              show-hotkey-overlay = [ ];
            };
            "Mod+Shift+E".action = {
              quit = [ ];
            };
            "Mod+Shift+P".action = {
              power-off-monitors = [ ];
            };

            "Mod+V".action.spawn = [
              "sh"
              "-c"
              "cliphist list | wofi --dmenu -p 'Clipboard' | cliphist decode | wl-copy"
            ];
            "Mod+E".action.spawn = [ "emote" ];
            "Mod+Shift+Ctrl+R".action.spawn = [ "toggle-recording" ];
          };

          spawn-at-startup = [
            {
              argv = [
                "nm-applet"
                "--indicator"
              ];
            }
            { argv = [ "blueman-applet" ]; }
            {
              argv = [
                "wl-paste"
                "--watch"
                "cliphist"
                "store"
              ];
            }
          ];

          window-rules = [
            {
              matches = [ { app-id = "nm-connection-editor"; } ];
              open-floating = true;
            }
            {
              matches = [ { app-id = "blueman-manager"; } ];
              open-floating = true;
            }
            {
              matches = [ { title = "Authentication Required"; } ];
              open-floating = true;
            }
            {
              matches = [ { title = "Picture-in-Picture"; } ];
              open-floating = true;
            }
          ];
        };

        noctalia = {
          enable = true;
          systemd.enable = true;
          settings = {
            settingsVersion = 0;
            general = {
              avatarImage = "~/.face";
              dimmerOpacity = 0.2;
              showScreenCorners = false;
              compactLockScreen = true;
              lockOnSuspend = true;
              showSessionButtonsOnLockScreen = true;
              showChangelogOnStartup = false;
              telemetryEnabled = false;
              enableLockScreenCountdown = true;
              lockScreenCountdownDuration = 10000;
            };
            bar = {
              barType = "floating";
              position = "bottom";
              density = "default";
              showOutline = false;
              showCapsule = true;
              floating = true;
              marginVertical = 4;
              marginHorizontal = 8;
              frameThickness = 8;
              frameRadius = 12;
              displayMode = "always_visible";
              widgets = {
                left = [
                  { id = "ActiveWindow"; }
                  { id = "Clock"; }
                ];
                center = [
                  {
                    id = "Workspace";
                    labelMode = "index";
                    showApplications = true;
                    showBadge = true;
                    iconScale = 0.8;
                    pillSize = 0.6;
                  }
                ];
                right = [
                  { id = "Tray"; }
                  { id = "Battery"; }
                  { id = "Volume"; }
                  { id = "ControlCenter"; }
                ];
              };
            };
            appLauncher = {
              enableClipboardHistory = true;
              enableClipPreview = true;
              position = "center";
              terminalCommand = "kitty";
              viewMode = "list";
              showCategories = true;
            };
            controlCenter = {
              position = "close_to_bar_button";
              diskPath = "/";
              shortcuts = {
                left = [
                  { id = "Network"; }
                  { id = "Bluetooth"; }
                  { id = "WallpaperSelector"; }
                ];
                right = [
                  { id = "Notifications"; }
                  { id = "PowerProfile"; }
                  { id = "NightLight"; }
                ];
              };
              cards = [
                {
                  enabled = true;
                  id = "profile-card";
                }
                {
                  enabled = true;
                  id = "shortcuts-card";
                }
                {
                  enabled = true;
                  id = "audio-card";
                }
                {
                  enabled = false;
                  id = "brightness-card";
                }
                {
                  enabled = true;
                  id = "media-sysmon-card";
                }
              ];
            };
            notifications = {
              enabled = true;
              location = "top_right";
              backgroundOpacity = 1;
              lowUrgencyDuration = 3;
              normalUrgencyDuration = 8;
              criticalUrgencyDuration = 15;
            };
            osd = {
              enabled = true;
              location = "top_right";
              autoHideMs = 2000;
            };
            audio = {
              volumeStep = 5;
              volumeOverdrive = false;
            };
            brightness = {
              brightnessStep = 5;
              enforceMinimum = true;
              enableDdcSupport = false;
            };
            nightLight = {
              enabled = true;
              autoSchedule = true;
              nightTemp = "3500";
              dayTemp = "6500";
            };
            wallpaper = {
              enabled = true;
              directory = "~/Pictures/Wallpapers";
              fillMode = "crop";
              useSolidColor = true;
              solidColor = "#1e1e2e";
            };
            sessionMenu = {
              enableCountdown = true;
              countdownDuration = 10000;
              largeButtonsStyle = true;
              powerOptions = [
                {
                  action = "lock";
                  enabled = true;
                }
                {
                  action = "suspend";
                  enabled = true;
                }
                {
                  action = "reboot";
                  enabled = true;
                }
                {
                  action = "logout";
                  enabled = true;
                }
                {
                  action = "shutdown";
                  enabled = true;
                }
              ];
            };
            colorSchemes = {
              useWallpaperColors = false;
              predefinedScheme = "catppuccin-mocha";
              darkMode = true;
            };
            ui = {
              fontDefault = "JetBrainsMono Nerd Font";
              fontFixed = "JetBrainsMono Nerd Font Mono";
              fontDefaultScale = 1;
              fontFixedScale = 1;
            };
          };
        };

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
      };

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
        };
      };

      home.packages = with pkgs; [
        kitty
        wl-clipboard
        cliphist
        wofi
        grimblast
        emote
        wf-recorder
        toggle-recording
        libnotify
        playerctl
        brightnessctl
        networkmanagerapplet
        pavucontrol
        nirimod
      ];
    };
}
