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

      luaConfig = ''
        hl.monitor({output="eDP-1", mode="preferred", position="0x0", scale="1"})
        hl.monitor({output="", mode="preferred", position="auto", scale="1"})

        hl.env("WLR_NO_HARDWARE_CURSORS", "1")
        hl.env("GBM_BACKEND", "nvidia-drm")
        hl.env("XCURSOR_SIZE", "24")
        hl.env("HYPRCURSOR_SIZE", "24")

        hl.plugin.load("${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so")

        hl.config({
          general = { gaps_in=4, gaps_out=8, border_size=2,
            col = { active_border="rgb(cba6f7)", inactive_border="rgb(45475a)" },
            layout = "dwindle" },
          decoration = { rounding=8, active_opacity=1.0, inactive_opacity=0.9,
            shadow = { enabled=true, range=16, render_power=2,
              color="rgba(00000055)" },
            blur = { enabled=true, size=4, passes=2, new_optimizations=true } },
          input = { kb_layout="us", follow_mouse=1,
            touchpad = { natural_scroll=true } },
          gestures = { workspace_swipe=true },
          misc = { disable_hyprland_logo=true, enable_swallow=true,
            swallow_regex="^(kitty)$" },
        })

        local m = "SUPER"
        hl.bind(m.." + Return", hl.dsp.exec_cmd("kitty"))
        hl.bind(m.." + D", hl.dsp.exec_cmd("hyprlauncher"))
        hl.bind(m.." + Q", hl.dsp.window.close())
        hl.bind(m.." + Escape", hl.dsp.exec_cmd("hyprlock"))
        hl.bind(m.." + F", hl.dsp.window.fullscreen())
        hl.bind(m.." + Space", hl.dsp.window.float({action="toggle"}))
        hl.bind(m.." + H", hl.dsp.focus({direction="l"}))
        hl.bind(m.." + J", hl.dsp.focus({direction="d"}))
        hl.bind(m.." + K", hl.dsp.focus({direction="u"}))
        hl.bind(m.." + L", hl.dsp.focus({direction="r"}))
        hl.bind(m.." + SHIFT + H", hl.dsp.window.move({direction="l"}))
        hl.bind(m.." + SHIFT + J", hl.dsp.window.move({direction="d"}))
        hl.bind(m.." + SHIFT + K", hl.dsp.window.move({direction="u"}))
        hl.bind(m.." + SHIFT + L", hl.dsp.window.move({direction="r"}))
        for i=0,9 do hl.bind(m.." + "..((i==0) and "0" or tostring(i)),
          hl.dsp.focus({workspace=i}))
          hl.bind(m.." + SHIFT + "..((i==0) and "0" or tostring(i)),
            hl.dsp.window.move({workspace=i})) end
        hl.bind(m.." + mouse:272", hl.dsp.window.drag(), {mouse=true})
        hl.bind(m.." + mouse:273", hl.dsp.window.resize(), {mouse=true})
        hl.bind("XF86AudioRaiseVolume",
          hl.dsp.exec_cmd("swayosd-client --output-volume +5"),
          {locked=true, repeating=true})
        hl.bind("XF86AudioLowerVolume",
          hl.dsp.exec_cmd("swayosd-client --output-volume -5"),
          {locked=true, repeating=true})
        hl.bind("XF86AudioMute",
          hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"),
          {locked=true})
        hl.bind("XF86MonBrightnessUp",
          hl.dsp.exec_cmd("brightnessctl s +5%"),
          {locked=true, repeating=true})
        hl.bind("XF86MonBrightnessDown",
          hl.dsp.exec_cmd("brightnessctl s 5%-"),
          {locked=true, repeating=true})

        hl.on("hyprland.start", function()
          hl.exec_cmd("hyprpanel")
          hl.exec_cmd("nm-applet --indicator")
          hl.exec_cmd("blueman-applet")
          hl.exec_cmd("wl-paste --watch cliphist store")
          hl.exec_cmd("swayosd-server")
        end)

        hl.window_rule({match={class="nm-connection-editor"}, float=true})
        hl.window_rule({match={class="blueman-manager"}, float=true})
        hl.window_rule({match={title="Authentication Required"}, float=true})
        hl.window_rule({match={title="Picture-in-Picture"}, float=true, pin=true})
      '';
    in
    {
      xdg.configFile."hypr/hyprland.lua".text = luaConfig;
      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
        plugins = [ ];
        systemd.enable = false;
        settings = { };
        extraConfig = "";
      };

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

      programs.hyprlock = {
        enable = true;
        settings = {
          general.hide_cursor = true;
          background = {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          };
          input-field = {
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
            position = "0, -80";
          };
          label = [
            {
              text = "cmd[update:1000] echo \"$(date +'%H:%M')\"";
              color = "rgb(cdd6f4)";
              font_size = 96;
              position = "0, 40";
            }
          ];
        };
      };

      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "hyprctl dispatch exec hyprlock";
            before_sleep_cmd = "hyprctl dispatch exec hyprlock";
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
          ];
        };
      };

      services.hyprpolkitagent.enable = true;

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

      home.packages = with pkgs; [
        hyprlauncher
        hyprpanel
        hyprshot
        hyprpicker
        hyprkeys
        hyprnotify
        hyprpaper
        hyprdim
        pyprland
        kitty
        cliphist
        wl-clipboard
        swayosd
        wofi
        emote
        wf-recorder
        libnotify
        toggle-recording
        playerctl
        networkmanagerapplet
      ];
    };
}
