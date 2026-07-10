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
      xdg.configFile."niri/config.kdl".text = ''
        input {
            keyboard {
                xkb { layout "us"; }
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

        layout {
            gaps 12
            focus-ring { width 3; active-color "#cba6f7"; }
            border { off; }
            default-column-width { proportion 0.5; }
            center-focused-column "always"
            background-color "#1e1e2e"
        }

        cursor {
            xcursor-theme "catppuccin-mocha-mauve-cursors"
            xcursor-size 24
            hide-when-typing
        }

        screenshot-path "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png"
        prefer-no-csd

        environment {
            QT_QPA_PLATFORM "wayland;xcb"
            QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
        }

        // ── Binds ────────────────────────────────────────────────────
        // Audio, brightness, notification, session keys handled by Noctalia.
        binds {
            Mod+Return { spawn "kitty"; }
            Mod+Q { close-window; }
            Mod+Space { toggle-window-floating; }
            Mod+Shift+V { switch-focus-between-floating-and-tiling; }

            Mod+H { focus-column-left; }
            Mod+J { focus-window-down; }
            Mod+K { focus-window-up; }
            Mod+L { focus-column-right; }
            Mod+Home { focus-column-first; }
            Mod+End  { focus-column-last; }

            Mod+Ctrl+H { move-column-left; }
            Mod+Ctrl+J { move-window-down; }
            Mod+Ctrl+K { move-window-up; }
            Mod+Ctrl+L { move-column-right; }
            Mod+Ctrl+Home { move-column-to-first; }
            Mod+Ctrl+End  { move-column-to-last; }

            Mod+Shift+H { focus-monitor-left; }
            Mod+Shift+J { focus-monitor-down; }
            Mod+Shift+K { focus-monitor-up; }
            Mod+Shift+L { focus-monitor-right; }

            Mod+Shift+Ctrl+H { move-column-to-monitor-left; }
            Mod+Shift+Ctrl+J { move-column-to-monitor-down; }
            Mod+Shift+Ctrl+K { move-column-to-monitor-up; }
            Mod+Shift+Ctrl+L { move-column-to-monitor-right; }

            Mod+Alt+H { move-workspace-to-monitor-left; }
            Mod+Alt+J { move-workspace-to-monitor-down; }
            Mod+Alt+K { move-workspace-to-monitor-up; }
            Mod+Alt+L { move-workspace-to-monitor-right; }

            Mod+1 { focus-workspace 1; }
            Mod+2 { focus-workspace 2; }
            Mod+3 { focus-workspace 3; }
            Mod+4 { focus-workspace 4; }
            Mod+5 { focus-workspace 5; }
            Mod+6 { focus-workspace 6; }
            Mod+7 { focus-workspace 7; }
            Mod+8 { focus-workspace 8; }
            Mod+9 { focus-workspace 9; }
            Mod+0 { focus-workspace 10; }

            Mod+Ctrl+1 { move-column-to-workspace 1; }
            Mod+Ctrl+2 { move-column-to-workspace 2; }
            Mod+Ctrl+3 { move-column-to-workspace 3; }
            Mod+Ctrl+4 { move-column-to-workspace 4; }
            Mod+Ctrl+5 { move-column-to-workspace 5; }
            Mod+Ctrl+6 { move-column-to-workspace 6; }
            Mod+Ctrl+7 { move-column-to-workspace 7; }
            Mod+Ctrl+8 { move-column-to-workspace 8; }
            Mod+Ctrl+9 { move-column-to-workspace 9; }

            Mod+Page_Down { focus-workspace-down; }
            Mod+Page_Up   { focus-workspace-up; }
            Mod+U { focus-workspace-down; }
            Mod+I { focus-workspace-up; }
            Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
            Mod+Ctrl+Page_Up   { move-column-to-workspace-up; }
            Mod+Shift+Page_Down { move-workspace-down; }
            Mod+Shift+Page_Up   { move-workspace-up; }
            Mod+Shift+U { move-workspace-down; }
            Mod+Shift+I { move-workspace-up; }
            Mod+Tab { focus-workspace-previous; }

            Mod+Comma  { consume-window-into-column; }
            Mod+Period { expel-window-from-column; }
            Mod+BracketLeft  { consume-or-expel-window-left; }
            Mod+BracketRight { consume-or-expel-window-right; }

            Mod+R { switch-preset-column-width; }
            Mod+Shift+R { switch-preset-column-width-back; }
            Mod+Alt+R { reset-window-height; }
            Mod+Minus { set-column-width "-10%"; }
            Mod+Equal { set-column-width "+10%"; }
            Mod+Shift+Minus { set-window-height "-10%"; }
            Mod+Shift+Equal { set-window-height "+10%"; }

            Mod+F { maximize-column; }
            Mod+Shift+F { fullscreen-window; }
            Mod+M { maximize-window-to-edges; }
            Mod+Ctrl+F { expand-column-to-available-width; }

            Mod+C { center-column; }
            Mod+Ctrl+C { center-visible-columns; }
            Mod+W { toggle-column-tabbed-display; }
            Mod+O { toggle-overview; }

            Mod+WheelScrollDown      cooldown-ms=150 { focus-workspace-down; }
            Mod+WheelScrollUp        cooldown-ms=150 { focus-workspace-up; }
            Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
            Mod+Ctrl+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

            Print { screenshot; }
            Ctrl+Print { screenshot-screen; }

            Mod+Shift+Slash { show-hotkey-overlay; }
            Mod+Shift+E { quit; }
            Mod+Shift+P { power-off-monitors; }

            // Clipboard / recording
            Mod+V { spawn-sh "cliphist list | wofi --dmenu -p 'Clipboard' | cliphist decode | wl-copy"; }
            Mod+E { spawn "emote"; }
            Mod+Shift+Ctrl+R { spawn "toggle-recording"; }
        }

        // ── Spawn at startup ─────────────────────────────────────────
        // Noctalia handles bar, notifications, OSD, polkit, idle, lock.
        // Only non-Noctalia services are spawned here.
        spawn-at-startup "nm-applet" "--indicator"
        spawn-at-startup "blueman-applet"
        spawn-at-startup "wl-paste" "--watch" "cliphist" "store"

        // ── Window rules ─────────────────────────────────────────────
        window-rule { match app-id="nm-connection-editor"; open-floating true; }
        window-rule { match app-id="blueman-manager";     open-floating true; }
        window-rule { match title="Authentication Required"; open-floating true; }
        window-rule { match title="Picture-in-Picture";   open-floating true; }
      '';

      # ── Noctalia settings ──────────────────────────────────────────
      programs.noctalia = {
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
            position = "top";
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
                  showLabelsOnlyWhenOccupied = true;
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

      # ── HM-managed programs ──────────────────────────────────────
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

      # ── Packages not covered by Noctalia ──────────────────────────
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
