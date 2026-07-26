{
  aspects.homeManager.sway =
    { pkgs, ... }:
    let
      # Helper for the bidirectional PRIMARY ↔ CLIPBOARD bridge below.
      # Each `wl-paste --watch` invocation prints the new selection contents
      # to stdout whenever its watched selection changes; this script reads
      # that stdout and writes to the *other* selection via `wl-copy`.
      #
      # The CLI argument selects which selection to write to:
      #   --to-primary  → write to PRIMARY
      #   (anything else, default) → write to CLIPBOARD
      #
      # The steady-state short-circuit makes the bridge loop-free WITHOUT
      # relying on wlroots' implicit ownership-transfer dedup. When a watcher
      # sees its own write bounce back through the other watcher, the
      # incoming text already equals the destination's current contents — so
      # we skip the write entirely. The canonical implementation
      # (https://github.com/jreuben11/wayland-ricing-guide/blob/main/part-07-wayland-programming/ch125-data-control-clipboard.md#1256-primary-selection-middle-click-paste)
      # relies on the same property implicitly; we make it explicit so the
      # script costs zero round-trips in steady state.
      #
      # `runtimeInputs = [ pkgs.wl-clipboard ]` puts `wl-copy` / `wl-paste`
      # on PATH inside the script (hermetic, no `coreutils` / `bash` deps).
      clipboardBridge = pkgs.writeShellApplication {
        name = "clipboard-bridge";
        runtimeInputs = [ pkgs.wl-clipboard ];
        text = ''
          set -euo pipefail
          text=$(cat)
          other=$([ "''${1:-}" = "--to-primary" ] && echo --primary || echo "")
          # Skip empty payloads (the selection has been cleared).
          [ -n "$text" ] || exit 0
          current=$(wl-paste "$other" --no-newline 2>/dev/null || true)
          # Steady-state short-circuit — see the Nix-side comment above.
          [ "$text" != "$current" ] || exit 0
          printf %s "$text" | wl-copy "$other"
        '';
      };
    in
    {
      home.packages = with pkgs; [
        libnotify
        # Wayland/Sway utilities
        pavucontrol # PulseAudio volume control GUI
        nwg-displays # display configuration GUI
        nwg-look # GTK theme manager
      ];

      wayland.windowManager.sway = {
        enable = true;
        xwayland = true;
        config = rec {
          modifier = "Mod4";
          terminal = "ghostty";
          seat = {
            "*" = {
              xcursor_theme = "Adwaita 24";
            };
          };
          input = {
            "*" = {
              xkb_layout = "pl";
              repeat_delay = "250";
              repeat_rate = "50";
            };
            "type:touchpad" = {
              tap = "enabled";
              natural_scroll = "enabled";
              dwt = "enabled";
              pointer_accel = "0.3";
            };
          };
          # DMS owns the regular clipboard and its rich MIME types. PRIMARY
          # remains compositor/application-owned for middle-click pasting.
          startup = [ ];
          bars = [ ];
          keybindings = {
            "${modifier}+Return" = "exec ${terminal}";
            "${modifier}+Q" = "kill";
            # Toggle idle inhibit (prevent auto-lock/suspend during builds,
            # presentations, SSH sessions, etc.). DMS's built-in idle manager
            # only tracks local user input — it doesn't know about background
            # activity. Press again to re-enable idle.
            "${modifier}+i" = "exec dms ipc call inhibit toggle";
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
            "${modifier}+0" = "workspace number 10";
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
            "${modifier}+Shift+0" = "move container to workspace number 10";
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
            "${modifier}+Print" =
              "exec bash -c 'cd ~/Pictures/Screenshots && grim - | swappy -f - -o screenshot-$(date +%Y%m%d-%H%M%S).png && notify-send \"Screenshot saved\"'";
            "${modifier}+Ctrl+Shift+3" =
              "exec bash -c 'cd ~/Pictures/Screenshots && grim - | swappy -f - -o screenshot-$(date +%Y%m%d-%H%M%S).png && notify-send \"Screenshot saved\"'";
            "${modifier}+Ctrl+Print" =
              "exec bash -c 'cd ~/Pictures/Screenshots && grim -g \"$(slurp)\" - | swappy -f - -o screenshot-$(date +%Y%m%d-%H%M%S).png && notify-send \"Screenshot saved\"'";
            "${modifier}+Ctrl+Shift+4" =
              "exec bash -c 'cd ~/Pictures/Screenshots && grim -g \"$(slurp)\" - | swappy -f - -o screenshot-$(date +%Y%m%d-%H%M%S).png && notify-send \"Screenshot saved\"'";
            "XF86AudioRaiseVolume" = "exec dms ipc call audio increment 3";
            "XF86AudioLowerVolume" = "exec dms ipc call audio decrement 3";
            "XF86AudioMute" = "exec dms ipc call audio mute";
            "XF86AudioMicMute" = "exec dms ipc call audio micmute";
            "XF86MonBrightnessUp" = "exec dms ipc call brightness increment 5";
            "XF86MonBrightnessDown" = "exec dms ipc call brightness decrement 5";
            # DDC/CI monitor input switching
            "${modifier}+Insert" = "exec ${pkgs.ddcutil}/bin/ddcutil setvcp 0x60 0x0f";
            "${modifier}+Home" = "exec ${pkgs.ddcutil}/bin/ddcutil setvcp 0x60 0x0d";
          };
          # Window rules
          window = {
            commands = [
              {
                command = "floating enable";
                criteria = {
                  app_id = ".*\\.bitwarden";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  app_id = ".*\\.blueman-manager";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  app_id = "pavucontrol";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  app_id = "nwg-displays";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  app_id = "nwg-look";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  title = ".*File.*Open.*";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  title = ".*File.*Save.*";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  title = ".*Preferences.*";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  title = ".*Settings.*";
                };
              }
              {
                command = "floating enable";
                criteria = {
                  title = ".*About.*";
                };
              }
            ];
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

      # Bidirectional bridge between PRIMARY and CLIPBOARD: a text selection
      # (PRIMARY) populates CLIPBOARD for Ctrl+V, and Ctrl+C / DMS pastes
      # populate PRIMARY for middle-click.
      #
      # The primitive — two `wl-paste --watch` watchers, each writing to the
      # other selection — is the canonical recipe documented in the Wayland
      # Ricing Guide §125.6
      # (https://github.com/jreuben11/wayland-ricing-guide/blob/main/part-07-wayland-programming/ch125-data-control-clipboard.md#1256-primary-selection-middle-click-paste)
      # and shipped verbatim by vanillacode314/stow-dotfiles
      # (https://github.com/vanillacode314/stow-dotfiles). We NixOS-ify it
      # with two systemd user services and a `writeShellApplication` helper
      # script (the `clipboardBridge` binding above).
      #
      # `--type text` keeps image/file offers untouched so DMS still owns
      # rich MIME handling. The helper script compares incoming text against
      # the destination selection and skips the write when equal — that
      # gives us a steady-state zero round-trip bridge; the canonical
      # pipeline relies on the same property implicitly.
      #
      # Replaces the previous one-way `clipboard → PRIMARY` bridge (the
      # ArchWiki recipe, also kept by every Nix dotfile surveyed). That
      # bridge existed for Bitwarden, which writes secrets to the clipboard;
      # with the bidirectional bridge that flow still works, plus middle-click
      # paste now picks up the same secret.
      #
      # Requires the data-control Wayland protocol
      # (wlr-data-control-unstable-v1 or ext-data-control-v1). Sway supports
      # both — see modules/parts/clipboard-protocol-check.nix for the
      # KVM-backed invariant that proves this. Some compositors (notably
      # Mutter/GNOME) do not, which is why darkone-nixos-framework left the
      # same bridge commented out with a TODO.
      systemd.user.services = {
        clipboard-primary-sync = {
          Unit = {
            Description = "Copy PRIMARY text to CLIPBOARD";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --primary --type text --watch ${clipboardBridge}/bin/clipboard-bridge --to-clipboard";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        clipboard-clipboard-sync = {
          Unit = {
            Description = "Copy CLIPBOARD text to PRIMARY";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${clipboardBridge}/bin/clipboard-bridge --to-primary";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

      # Inhibit system sleep while any MPRIS media player (Spotify, etc.)
      # is actively playing.  Without this, DMS's acSuspendTimeout fires
      # after 10 min of keyboard/mouse idle even when audio is playing.
      #
      # Runs a single long-lived `systemd-inhibit` background process when
      # playback is detected, and kills it when playback stops.  This avoids
      # the race window of the per-iteration pattern where the inhibitor
      # lock is briefly released between polling cycles.
        media-sleep-inhibit = {
          Unit = {
            Description = "Inhibit sleep while MPRIS media is playing";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${
              pkgs.writeShellApplication {
                name = "media-sleep-inhibit";
                runtimeInputs = [
                  pkgs.playerctl
                  pkgs.systemd
                ];
                text = ''
                  INTERVAL=15
                  inhibitor_pid=""

                  cleanup() {
                    if [ -n "$inhibitor_pid" ]; then
                      kill "$inhibitor_pid" 2>/dev/null || true
                    fi
                  }
                  trap cleanup EXIT

                  while true; do
                    if playerctl --all-players status 2>/dev/null | grep -q "Playing"; then
                      if [ -z "$inhibitor_pid" ]; then
                        systemd-inhibit --what=sleep --who="media-playback" --why="Media playing" sleep infinity &
                        inhibitor_pid=$!
                      fi
                    else
                      if [ -n "$inhibitor_pid" ]; then
                        kill "$inhibitor_pid" 2>/dev/null || true
                        wait "$inhibitor_pid" 2>/dev/null || true
                        inhibitor_pid=""
                      fi
                    fi
                    sleep "$INTERVAL"
                  done
                '';
              }
            }/bin/media-sleep-inhibit";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };

      services.wlsunset = {
        enable = true;
        latitude = "52.2";
        longitude = "21.0";
      };

      gtk = {
        enable = true;
        theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
        cursorTheme = {
          name = "Adwaita";
          size = 24;
          package = pkgs.adwaita-icon-theme;
        };
      };

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Adwaita-dark";
          cursor-theme = "Adwaita";
          cursor-size = 24;
        };
      };
    };
}
