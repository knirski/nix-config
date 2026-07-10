{
  aspects.homeManager.hyprland =
    { pkgs, ... }:
    {
      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
        plugins = [ pkgs.hyprlandPlugins.hy3 ];

        settings = {
          monitor = [
            "eDP-1,preferred,0x0,1"
            ",preferred,auto,1"
          ];

          "$mod" = "SUPER";
          bind = [
            "$mod, Return, exec, ghostty"
            "$mod, d,      exec, hyprlauncher"
            "$mod, q,      killactive,"
            "$mod, Escape, exec, hyprlock"
            "$mod, f,      fullscreen"
            "$mod, Space,  togglefloating,"

            "$mod, h, movefocus, l"
            "$mod, j, movefocus, d"
            "$mod, k, movefocus, u"
            "$mod, l, movefocus, r"

            "$mod SHIFT, h, movewindow, l"
            "$mod SHIFT, j, movewindow, d"
            "$mod SHIFT, k, movewindow, u"
            "$mod SHIFT, l, movewindow, r"

            "$mod, 1, workspace, 1"
            "$mod SHIFT, 1, movetoworkspace, 1"
            "$mod, 2, workspace, 2"
            "$mod SHIFT, 2, movetoworkspace, 2"
            "$mod, 3, workspace, 3"
            "$mod SHIFT, 3, movetoworkspace, 3"
            "$mod, 4, workspace, 4"
            "$mod SHIFT, 4, movetoworkspace, 4"
            "$mod, 5, workspace, 5"
            "$mod SHIFT, 5, movetoworkspace, 5"
            "$mod, 6, workspace, 6"
            "$mod SHIFT, 6, movetoworkspace, 6"
            "$mod, 7, workspace, 7"
            "$mod SHIFT, 7, movetoworkspace, 7"
            "$mod, 8, workspace, 8"
            "$mod SHIFT, 8, movetoworkspace, 8"
            "$mod, 9, workspace, 9"
            "$mod SHIFT, 9, movetoworkspace, 9"

            "$mod, comma, movetoworkspace, special"
            "$mod, period, togglespecialworkspace,"

            # Media keys
            ", XF86AudioRaiseVolume, exec, pamixer -i 5"
            ", XF86AudioLowerVolume, exec, pamixer -d 5"
            ", XF86AudioMute,        exec, pamixer -t"
            ", XF86AudioPlay,        exec, playerctl play-pause"
            ", XF86AudioNext,        exec, playerctl next"
            ", XF86AudioPrev,        exec, playerctl previous"
            ", XF86MonBrightnessUp,   exec, brightnessctl s +5%"
            ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"

            # Screenshots (hyprshot — native hyprland region capture)
            ", Print, exec, hyprshot -m region -z -s --clipboard-only"
            "$mod SHIFT, Print, exec, hyprshot -m output -z -s"
            "$mod CTRL, Print, exec, hyprshot -m region -z -o ~/Pictures/Screenshots"

            # hyprkeys — show keybinding overlay
            "$mod SHIFT, slash, exec, hyprkeys"

            # hy3: i3-style manual tiling
            "SUPER, r, hy3:change_ratio,"
            "SUPER, v, hy3:change_split_direction,"
            "SUPER, t, hy3:change_concurrency, 0" # toggle tab
            "SUPER, g, hy3:make_group,"
            "SUPER SHIFT, g, hy3:make_detached,"
            "SUPER, u, hy3:change_concurrency, 2" # tab mode
            "SUPER, y, hy3:change_concurrency, 1" # stack mode
            "$mod CTRL, c, exec, hyprpicker -a -f hex"
          ];

          bindm = [
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
          ];

          windowrulev2 = [
            "float, class:(nm-connection-editor)"
            "float, class:(blueman-manager)"
            "float, title:(Authentication Required)"
            "float, title:(Picture-in-Picture)"
            "pin,    title:(Picture-in-Picture)"
            "noborder, fullscreen:1"
          ];

          general = {
            gaps_in = 4;
            gaps_out = 8;
            border_size = 2;
            "col.active_border" = "rgb(cba6f7)";
            "col.inactive_border" = "rgb(45475a)";
            layout = "hy3";
            cursor_inactive_timeout = 3;
          };

          decoration = {
            rounding = 8;
            active_opacity = 1.0;
            inactive_opacity = 0.9;
            drop_shadow = true;
            shadow_range = 16;
            shadow_render_power = 2;
            "col.shadow" = "rgba(00000055)";
            blur = {
              enabled = true;
              size = 4;
              passes = 2;
              new_optimizations = true;
            };
          };

          input = {
            kb_layout = "us";
            follow_mouse = 1;
            touchpad.natural_scroll = true;
            sensitivity = 0;
          };

          gestures.workspace_swipe = true;

          misc = {
            enable_swallow = true;
            swallow_regex = "^(ghostty)$";
            disable_hyprland_logo = true;
          };
        };

        extraConfig = ''
          env = WLR_NO_HARDWARE_CURSORS,1
          env = GBM_BACKEND,nvidia-drm
          env = __GLX_VENDOR_LIBRARY_NAME,nvidia
          env = LIBVA_DRIVER_NAME,nvidia

          exec-once = hyprpanel
          exec-once = nm-applet --indicator
          exec-once = blueman-applet
          exec-once = wl-paste --watch cliphist store
          exec-once = pypr
          exec-once = hyprdim
        '';
      };

      programs = {
        ghostty = {
          enable = true;
          enableBashIntegration = true;
          enableZshIntegration = true;
          settings = {
            theme = "catppuccin-mocha";
            font-family = "JetBrainsMono Nerd Font";
            font-size = 13;
            shell-integration = "/run/current-system/sw/bin/bash";
            gtk-titlebar = false;
            window-padding-x = 4;
            window-padding-y = 4;
            copy-on-select = "clipboard";
          };
        };

        yazi = {
          enable = true;
          enableBashIntegration = true;
          enableZshIntegration = true;
          settings = {
            manager = {
              show_hidden = true;
              sort_dir_first = true;
            };
            opener.rules = [
              {
                mime = "image/*";
                use = "imv";
              }
              {
                mime = "video/*";
                use = "mpv";
              }
              {
                mime = "application/pdf";
                use = "zathura";
              }
            ];
          };
        };

        hyprlock = {
          enable = true;
          settings = {
            general = {
              hide_cursor = true;
              no_fade_in = false;
            };
            background = {
              path = "screenshot";
              blur_passes = 3;
              blur_size = 8;
            };
            input-field = {
              monitor = "";
              size = "250, 60";
              outline_thickness = 3;
              dots_size = 0.2;
              dots_spacing = 0.4;
              dots_center = true;
              outer_color = "rgb(cba6f7)";
              inner_color = "rgb(1e1e2e)";
              font_color = "rgb(cdd6f4)";
              fade_on_empty = false;
              placeholder_text = "Password...";
              check_color = "rgb(a6e3a1)";
              fail_color = "rgb(f38ba8)";
              fail_text = "Wrong!";
              capslock_color = "rgb(f9e2af)";
              position = "0, -80";
              halign = "center";
              valign = "center";
            };
            label = [
              {
                monitor = "";
                text = "cmd[update:1000] echo \"$(date +'%H:%M')\"";
                color = "rgb(cdd6f4)";
                font_size = 96;
                font_family = "JetBrainsMono Nerd Font";
                position = "0, 40";
                halign = "center";
                valign = "center";
              }
            ];
          };
        };
      };

      services = {
        hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = "hyprctl dispatch exec hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on";
            };
            listener = [
              {
                timeout = 300;
                on-timeout = "hyprctl dispatch exec hyprlock";
              }
              {
                timeout = 600;
                on-timeout = "systemctl suspend";
              }
              {
                timeout = 120;
                on-timeout = "hyprctl dispatch dpms off";
                on-resume = "hyprctl dispatch dpms on";
              }
            ];
          };
        };

        hyprpolkitagent.enable = true;

        hyprsunset = {
          enable = true;
          settings = {
            profile = [
              {
                time = "06:00";
                temperature = 6500;
              }
              {
                time = "19:00";
                temperature = 3500;
              }
            ];
          };
        };

      };

      gtk = {
        enable = true;
        theme = {
          name = "catppuccin-mocha-mauve";
          package = pkgs.catppuccin-gtk.override {
            accents = [ "mauve" ];
            size = "standard";
            tweaks = [
              "normal"
              "rimless"
            ];
          };
        };
        cursorTheme = {
          name = "catppuccin-mocha-mauve-cursors";
          package = pkgs.catppuccin-cursors.mochaMauve;
        };
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.papirus-icon-theme;
        };
      };

      qt = {
        enable = true;
        platformTheme.name = "gtk3";
        style = {
          name = "kvantum";
          package = pkgs.catppuccin-kvantum;
        };
      };

      home.packages = with pkgs; [
        hyprlauncher
        hyprpanel
        hyprshot
        hyprmoncfg
        hyprpicker
        hyprkeys
        hyprnotify
        hyprpaper
        hyprdim
        pyprland
        ghostty
        yazi
        pwvucontrol
        cliphist
        wl-clipboard
        kanshi
        wlr-randr
        pamixer
        playerctl
        networkmanagerapplet
        catppuccin-kvantum
      ];
    };
}
