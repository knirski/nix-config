{
  aspects.homeManager.sway =
    { lib, pkgs, ... }:
    let
      # The shell preferences this repository insists on, recovered by diffing
      # the old 527-key settings.json dump against the `property` declarations
      # in DankMaterialShell's SettingsData.qml. Only 19 of those 527 keys
      # differed from the shell's own defaults; the rest was the shell
      # agreeing with itself, which is why generating the whole file bought
      # nothing and cost the shell its ability to persist anything.
      #
      # Eight of the 19 were deliberately unpinned and left at the shell's
      # defaults -- barElevationEnabled, barInsetPaddingSyncAll, cornerRadius,
      # displayNameMode, dockLauncherLogoColorOverride, dockLauncherLogoMode,
      # networkPreference and osdPowerProfileEnabled. They are appearance and
      # convenience toggles worth adjusting from the UI without Nix
      # reasserting them on the next activation. See the previous commit for
      # the values they held.
      #
      # What remains is behaviour that should be identical on a fresh machine:
      # when it locks, when it suspends, how it treats the battery, and the
      # two status icons that are easy to miss are missing.
      #
      # Re-applied over the live file on every activation.
      dmsPinnedSettings = {
        # Idle, lock and suspend behaviour
        acLockTimeout = 900;
        acSuspendTimeout = 3600;
        lockBeforeSuspend = true;
        lockScreenPowerOffMonitorsOnLock = true;
        # Power profiles and battery care
        acProfileName = "2";
        batteryProfileName = "1";
        batteryAutoPowerSaver = true;
        batteryChargeLimit = 80;
        # Workspace and control-centre indicators
        showWorkspaceIndex = true;
        controlCenterShowIdleInhibitorIcon = true;
        controlCenterShowMicPercent = false;
      };

      dmsPinnedFile = (pkgs.formats.json { }).generate "dms-pinned.json" dmsPinnedSettings;

      # Sway/wlroots has no primary-output setting -- X11 got one from
      # xrandr, Wayland never did. This make/model/serial identifier is the
      # closest thing to an identity for the docked iiyama: it survives DP
      # connector renumbering and is shared by the workspace assignments,
      # the login focus, and the XWayland primary watcher below.
      iiyama = "Iiyama North America PL2792Q 1152194804219";
    in
    {
      # DankMaterialShell owns its own settings.json. It used to be generated
      # wholesale from a 527-key dump, which made it a read-only store symlink:
      # the shell could not persist a single change from its UI, and anything
      # this repository wanted to set had to fight the same file -- the
      # wallpaper could not go there at all, and the lock command needed
      # mkForce.
      #
      # Now only dmsPinnedSettings above is enforced, merged over whatever the
      # shell has. Two ordering details matter. This runs *before*
      # linkGeneration, because that step deletes symlinks the new generation
      # no longer declares -- an entry ordered after it finds the old file
      # already gone and silently migrates nothing. And the merge is
      # `live * pinned`, so pinned keys win while the shell's own keys are
      # preserved.
      home.activation.dankMaterialShellSettings = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
        target="''${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/settings.json"
        run mkdir -p "$(dirname "$target")"

        # A symlink is the old store-managed file: keep its contents, drop the
        # link, so no setting is lost on the way out of wholesale management.
        if [ -L "$target" ]; then
          resolved=$(readlink -f "$target")
          run rm -f "$target"
          [ -f "$resolved" ] && run install -m 0644 "$resolved" "$target"
        fi

        if [ -f "$target" ]; then
          tmp=$(mktemp)
          if ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$target" ${dmsPinnedFile} >"$tmp"; then
            run install -m 0644 "$tmp" "$target"
          fi
          rm -f "$tmp"
        else
          run install -m 0644 ${dmsPinnedFile} "$target"
        fi
      '';

      home.packages = with pkgs; [
        libnotify
        # Wayland/Sway utilities
        pavucontrol # PulseAudio volume control GUI
        nwg-displays # display configuration GUI
        nwg-look # GTK theme manager
        xrandr # X11 (XWayland) output control: sets the primary output
      ];

      wayland.windowManager.sway = {
        enable = true;
        xwayland = true;
        config = rec {
          modifier = "Mod4";
          terminal = "ghostty";
          # Prefer the docked monitor for every workspace except 8. The
          # make/model/serial identifier survives DP connector renumbering;
          # eDP-1 is the fallback for the docked workspaces when undocked.
          workspaceOutputAssign = [
            {
              workspace = "1";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "2";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "3";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "4";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "5";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "6";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "7";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "8";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "9";
              output = [
                iiyama
                "eDP-1"
              ];
            }
            {
              workspace = "10";
              output = "eDP-1";
            }
          ];
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
          # Sway has no primary output; focusing the docked monitor at login
          # makes new windows and the DMS launcher open there. The command is
          # a harmless error in the sway log when undocked.
          startup = [
            {
              command = "swaymsg 'focus output \"${iiyama}\"'";
              always = false;
            }
          ];
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
            # Flameshot owns the interactive capture/annotation flow. It does
            # not receive a save path, so screenshots are only saved or copied
            # when chosen in its UI.
            "Print" = "exec flameshot gui";
            "Ctrl+${modifier}+s" = "exec flameshot gui";
            "XF86AudioRaiseVolume" = "exec dms ipc call audio increment 3";
            "XF86AudioLowerVolume" = "exec dms ipc call audio decrement 3";
            "XF86AudioMute" = "exec dms ipc call audio mute";
            "XF86AudioMicMute" = "exec dms ipc call audio micmute";
            "XF86MonBrightnessUp" = "exec dms ipc call brightness increment 5";
            "XF86MonBrightnessDown" = "exec dms ipc call brightness decrement 5";
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

        # Flameshot v14 captures through xdg-desktop-portal-wlr. Import the
        # compositor's runtime variables into the user manager and D-Bus so
        # portal-activated services can see the same Wayland session as Sway.
        # The window rule keeps the capture surface floating across monitors;
        # see https://github.com/flameshot-org/flameshot/blob/master/docs/UsageHyprlandSwayWlroots.md.
        extraConfig = ''
          exec ${pkgs.systemd}/bin/systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK
          exec ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
          for_window [app_id="flameshot"] border pixel 0, floating enable, fullscreen disable, move absolute position 0 0
        '';
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
            dankBitwarden = {
              enable = true;
              settings = {
                trigger = "bw";
                loginAction = "autotype";
                cardAction = "type:number";
                identityAction = "copy:name";
                sshKeyAction = "copy:public_key";
              };
            };
          };
        };

        dank-calendar = {
          enable = true;
          systemd.enable = true;
        };
      };

      # These services are enabled by the shared graphical-session target,
      # which display managers reuse for non-Sway sessions too (Regolith on
      # the Ubuntu host).  Keep the DMS stack out of X11 sessions so those
      # remain a usable fallback when Sway is not selected.
      #
      # Only the condition is shared.  The services' PATH is a host concern:
      # on NixOS the inherited systemd-user PATH is already correct, and
      # overriding it here would drop /run/current-system/sw/bin (where
      # ddcutil lives for DMS's DDC/CI brightness).  modules/parts/ubuntu.nix
      # sets it for standalone Home Manager, which has no such PATH.
      # Upstream wants both units from graphical-session.target.  That target
      # is activated once and then stays up, and systemd evaluates
      # ConditionEnvironment only at the start attempt: if anything reaches
      # graphical-session.target before Sway has pushed XDG_SESSION_TYPE into
      # the user manager (a crashed session attempt is enough), both units are
      # recorded as skipped and never retried for the rest of the login.
      # Also want them from sway-session.target, which Sway starts and stops
      # on every run, so a fresh compositor always gets a fresh start attempt.
      systemd.user.services = {
        dms = {
          Unit = {
            ConditionEnvironment = "XDG_SESSION_TYPE=wayland";
            PartOf = [ "sway-session.target" ];
            After = [ "sway-session.target" ];
          };
          Install.WantedBy = [ "sway-session.target" ];
        };
        dcal = {
          Unit = {
            ConditionEnvironment = "XDG_SESSION_TYPE=wayland";
            PartOf = [ "sway-session.target" ];
            After = [ "sway-session.target" ];
          };
          Install.WantedBy = [ "sway-session.target" ];
        };
      };

      # ── Clipboard architecture ────────────────────────────────────────────
      #
      # DMS owns the regular Wayland CLIPBOARD selection (history at Mod4+v).
      # PRIMARY remains compositor-owned for middle-click paste — no bridge
      # needed between the two on Sway.
      #
      # Canonical bridge from the Wayland Ricing Guide §125.6:
      #   https://github.com/jreuben11/wayland-ricing-guide/blob/main/part-07-wayland-programming/ch125-data-control-clipboard.md#1256-primary-selection-middle-click-paste
      #
      #   wl-paste --primary --watch wl-copy           # PRIMARY → CLIPBOARD
      #   wl-paste --watch wl-copy --primary           # CLIPBOARD → PRIMARY
      #
      # These were removed because they raced with each other (and with
      # DMS's clipboard watcher) when an XWayland app like Bitwarden copied
      # to the clipboard — both watchers fired simultaneously, each calling
      # `wl-copy` for the opposite selection, and wlroots could leave both
      # selections ownerless. This made pasting into Firefox (native Wayland)
      # silently fail.
      #
      # The trade-off: without the bridge, Bitwarden (XWayland Electron) sets
      # the clipboard through X11's protocol, which XWayland forwards but not
      # in a way that triggers DMS's Wayland-native clipboard monitor. So
      # passwords copied from Bitwarden won't appear in DMS's clipboard
      # history. They paste correctly — but aren't recorded.
      #
      # If you need both: restore the bridge and accept the race window
      # (typically resolves on retry), or switch to the Bitwarden browser
      # extension which works entirely inside Firefox (native Wayland) and
      # is visible to DMS.

      # Inhibit system sleep while any MPRIS media player (Spotify, etc.)
      # is actively playing.  Without this, DMS's acSuspendTimeout fires
      # after 10 min of keyboard/mouse idle even when audio is playing.
      #
      # Runs a single long-lived `systemd-inhibit` background process when
      # playback is detected, and kills it when playback stops.  This avoids
      # the race window of the per-iteration pattern where the inhibitor
      # lock is briefly released between polling cycles.
      systemd.user.services = {
        media-sleep-inhibit = {
          Unit = {
            Description = "Inhibit sleep while MPRIS media is playing";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            ConditionEnvironment = "XDG_SESSION_TYPE=wayland";
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

        # Sway/wlroots has no primary output, but X11 apps and games still ask
        # XWayland for one. XWayland 24.1+ exposes Wayland connector names to
        # xrandr, so the docked iiyama can be re-marked primary by name. A
        # dock/undock or DPMS cycle recreates the XWayland outputs and drops
        # the flag, so stay subscribed to sway output events instead of setting
        # it once at startup. Undocked, the marker falls back to the laptop
        # panel so X11 apps never lose a primary output (sway itself already
        # moves focus and workspaces back on unplug, and onto the iiyama on
        # replug).
        xwayland-primary = {
          Unit = {
            Description = "Keep the iiyama as the XWayland primary output";
            After = [ "sway-session.target" ];
            PartOf = [ "sway-session.target" ];
            ConditionEnvironment = "XDG_SESSION_TYPE=wayland";
          };
          Service = {
            ExecStart = "${
              pkgs.writeShellApplication {
                name = "xwayland-primary";
                runtimeInputs = [
                  pkgs.coreutils
                  pkgs.jq
                  pkgs.sway
                  pkgs.xrandr
                ];
                text = ''
                    identifier=${lib.escapeShellArg iiyama}

                  # Resolve the connector from the make/model/serial identifier
                  # (DP-* is not stable across docks), then mark it primary.
                  # Undocked, prefer the laptop panel; any active output beats
                  # none. The bounded retry covers XWayland still enumerating
                  # outputs after the sway event that woke us.
                  set_primary() {
                    attempt=0
                    while [ "$attempt" -lt 20 ]; do
                      if outputs=$(swaymsg -t get_outputs 2>/dev/null); then
                        connector=$(printf '%s' "$outputs" | jq -r --arg id "$identifier" \
                          '.[] | select(.active and ("\(.make) \(.model) \(.serial)" == $id)) | .name' | head -n 1)
                        if [ -z "$connector" ]; then
                          connector=$(printf '%s' "$outputs" | jq -r \
                            '[.[] | select(.active and .name == "eDP-1")][0].name // empty')
                        fi
                        if [ -z "$connector" ]; then
                          connector=$(printf '%s' "$outputs" | jq -r \
                            '[.[] | select(.active)][0].name // empty')
                        fi
                        [ -n "$connector" ] || return 0
                        if xrandr --output "$connector" --primary 2>/dev/null; then
                          return 0
                        fi
                      fi
                      attempt=$((attempt + 1))
                      sleep 0.5
                    done
                    return 0
                  }

                    set_primary
                    swaymsg -t subscribe -m '["output"]' | while read -r _; do
                      set_primary
                    done
                '';
              }
            }/bin/xwayland-primary";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "sway-session.target" ];
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
