{
  aspects.homeManager.hyprland =
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
      # Temporary: Hyprland 0.55+ defaults to Lua config. HM still generates
      # hyprland.conf, so write a parallel hyprland.lua mirroring the HM settings.
      # When HM adds native Lua support, remove this block and let HM generate lua.
      xdg.configFile."hypr/hyprland.lua".text = ''
        -- Generated from HM module. Remove once HM supports Lua natively.

        hl.monitor({
            output   = "eDP-1",
            mode     = "preferred",
            position = "0x0",
            scale    = "1",
        })
        hl.monitor({
            output   = "",
            mode     = "preferred",
            position = "auto",
            scale    = "1",
        })

        local mainMod = "SUPER"

        -- Autostart
        hl.on("hyprland.start", function()
            hl.exec_cmd("hyprctl plugin load ${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so")
            hl.exec_cmd("hyprpanel")
            hl.exec_cmd("nm-applet --indicator")
            hl.exec_cmd("blueman-applet")
            hl.exec_cmd("wl-paste --watch cliphist store")
            hl.exec_cmd("pypr")
            hl.exec_cmd("hyprdim")
            hl.exec_cmd("hyprnotify")
            hl.exec_cmd("swayosd-server")
        end)

        -- Environment
        hl.env("WLR_NO_HARDWARE_CURSORS", "1")
        hl.env("GBM_BACKEND", "nvidia-drm")
        hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
        hl.env("LIBVA_DRIVER_NAME", "nvidia")
        hl.env("XCURSOR_SIZE", "24")

        -- Keybinds
        hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("kitty"))
        hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd("hyprlauncher"))
        hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
        hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("hyprlock"))
        hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen())
        hl.bind(mainMod .. " + Space",  hl.dsp.window.float({ action = "toggle" }))

        hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
        hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
        hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
        hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))

        hl.bind(mainMod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
        hl.bind(mainMod .. " + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
        hl.bind(mainMod .. " + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
        hl.bind(mainMod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right" }))

        for i = 1, 9 do
            local key = i % 10
            hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
            hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
        end

        hl.bind(mainMod .. " + comma",  hl.dsp.window.move({ workspace = "special" }))
        hl.bind(mainMod .. " + period", hl.dsp.workspace.toggle_special())

        -- Media keys
        hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume +5"),   { locked = true, repeating = true })
        hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume -5"),   { locked = true, repeating = true })
        hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true })
        hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"),                { locked = true })
        hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),                      { locked = true })
        hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),                  { locked = true })
        hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s +5%"),                { locked = true, repeating = true })
        hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"),                { locked = true, repeating = true })

        -- Screenshots
        hl.bind("Print",            hl.dsp.exec_cmd("hyprshot -m region -z -s --clipboard-only"))
        hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m output -z -s"))
        hl.bind(mainMod .. " + CTRL + Print",  hl.dsp.exec_cmd("hyprshot -m region -z -o ~/Pictures/Screenshots"))

        -- hyprkeys overlay
        hl.bind(mainMod .. " + SHIFT + slash", hl.dsp.exec_cmd("hyprkeys"))

        -- hy3 dispatchers (via hyprctl dispatch)
        hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("hyprctl dispatch hy3:change_ratio"))
        hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("hyprctl dispatch hy3:change_split_direction"))
        hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("hyprctl dispatch hy3:change_concurrency 0"))
        hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("hyprctl dispatch hy3:make_group"))
        hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd("hyprctl dispatch hy3:make_detached"))
        hl.bind(mainMod .. " + U", hl.dsp.exec_cmd("hyprctl dispatch hy3:change_concurrency 2"))
        hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd("hyprctl dispatch hy3:change_concurrency 1"))

        -- Clipboard history
        hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("cliphist list | wofi --dmenu -p 'Clipboard' | cliphist decode | wl-copy"))

        -- Emoji picker
        hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("emote"))

        -- Screen recording toggle
        hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("toggle-recording"))

        -- Color picker
        hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd("hyprpicker -a -f hex"))

        -- Mouse binds
        hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
        hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

        -- Window rules
        hl.window_rule({
            name  = "float-nm-editor",
            match = { class = "nm-connection-editor" },
            float = true,
        })
        hl.window_rule({
            name  = "float-blueman",
            match = { class = "blueman-manager" },
            float = true,
        })
        hl.window_rule({
            name  = "float-auth-required",
            match = { title = "Authentication Required" },
            float = true,
        })
        hl.window_rule({
            name  = "float-pip",
            match = { title = "Picture-in-Picture" },
            float = true,
            pin   = true,
        })
        hl.window_rule({
            name  = "fs-noborder",
            match = { fullscreen = 1 },
            no_border = true,
        })

        -- General config
        hl.config({
            general = {
                gaps_in  = 4,
                gaps_out = 8,
                border_size = 2,

                col = {
                    active_border   = "rgb(cba6f7)",
                    inactive_border = "rgb(45475a)",
                },

                layout            = "hy3",
                cursor_inactive_timeout = 3,
            },
        })

        -- Decoration
        hl.config({
            decoration = {
                rounding       = 8,
                active_opacity   = 1.0,
                inactive_opacity = 0.9,

                drop_shadow  = true,
                shadow = {
                    range        = 16,
                    render_power = 2,
                    color        = "rgba(00000055)",
                },

                blur = {
                    enabled = true,
                    size    = 4,
                    passes  = 2,
                    new_optimizations = true,
                },
            },
        })

        -- Input
        hl.config({
            input = {
                kb_layout  = "us",
                follow_mouse = 1,

                touchpad = {
                    natural_scroll = true,
                },

                sensitivity = 0,
            },
        })

        -- Gestures
        hl.gesture({
            fingers   = 3,
            direction = "horizontal",
            action    = "workspace",
        })

        -- Misc
        hl.config({
            misc = {
                enable_swallow = true,
                swallow_regex  = "^(kitty)$",
                disable_hyprland_logo = true,
            },
        })
      '';

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
            "$mod, Return, exec, kitty"
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

            # Media keys (volume OSD via swayosd)
            ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume +5"
            ", XF86AudioLowerVolume, exec, swayosd-client --output-volume -5"
            ", XF86AudioMute,        exec, swayosd-client --output-volume mute-toggle"
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
            "SUPER, s, hy3:change_split_direction,"
            "SUPER, t, hy3:change_concurrency, 0" # toggle tab
            "SUPER, g, hy3:make_group,"
            "SUPER SHIFT, g, hy3:make_detached,"
            "SUPER, u, hy3:change_concurrency, 2" # tab mode
            "SUPER, y, hy3:change_concurrency, 1" # stack mode
            # Clipboard history
            "$mod, v, exec, cliphist list | wofi --dmenu -p 'Clipboard' | cliphist decode | wl-copy"
            # Emoji picker
            "$mod, e, exec, emote"
            # Screen recording toggle
            "$mod SHIFT, r, exec, toggle-recording"
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
            swallow_regex = "^(kitty)$";
            disable_hyprland_logo = true;
          };
        };

        extraConfig = ''
          env = WLR_NO_HARDWARE_CURSORS,1
          env = GBM_BACKEND,nvidia-drm
          env = __GLX_VENDOR_LIBRARY_NAME,nvidia
          env = LIBVA_DRIVER_NAME,nvidia
          env = XCURSOR_SIZE,24

          exec-once = hyprpanel
          exec-once = nm-applet --indicator
          exec-once = blueman-applet
          exec-once = wl-paste --watch cliphist store
          exec-once = pypr
          exec-once = hyprdim
          exec-once = hyprnotify
          exec-once = swayosd-server
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
              before_sleep_cmd = "hyprctl dispatch exec hyprlock";
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
        kitty
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
        swayosd
        wofi
        emote
        wf-recorder
        libnotify
        toggle-recording
      ];
    };
}
