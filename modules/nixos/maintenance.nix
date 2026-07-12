{
  aspects.nixos.maintenance =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.maintenance;
    in
    {
      options.lanAppliance.services.maintenance = {
        enable = lib.mkEnableOption "scheduled maintenance (gc, scrub, smartd, timesyncd, free-space alerts, ntfy OnFailure)";
        ntpServers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "162.159.200.123" # Cloudflare NTP — IP only, no hostname to avoid
            "162.159.200.1" # boot-ordering deadlock (DNS → DoH → valid time).
          ];
          description = "NTP servers by IP, not hostname — avoids a boot-ordering deadlock where time sync depends on DNS which depends on DoH TLS which needs valid time.";
        };
        freeSpaceThreshold = lib.mkOption {
          type = lib.types.int;
          default = 85;
          description = "Disk usage percent threshold for ntfy alert. Uses btrfs filesystem usage, not df, because df is misleading on Btrfs.";
        };
        smartdDevices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "/dev/disk/by-id/ata-PELADN_512GB_20250522100164" ];
          description = "Disks monitored by smartd with self-test schedule (short daily 02:00, long Sunday 03:00).";
        };
      };

      config = lib.mkIf cfg.enable {
        # --- nix.gc: automated store cleanup ---
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 30d";
        };

        # --- journald: bounded log size ---
        # --- timesyncd: IP-based NTP servers ---
        # --- smartd: disk self-tests ---
        services = {
          journald.extraConfig = ''
            SystemMaxUse=500M
          '';
          timesyncd.enable = true;
          smartd = {
            enable = true;
            devices = map (dev: {
              device = dev;
              options = "-s (S/../.././02|L/../../7/03)";
            }) cfg.smartdDevices;
          };
        };
        networking.timeServers = cfg.ntpServers;

        # --- ntfy OnFailure: individual service drop-ins ---
        # Set on services defined in this module (global drop-ins via
        # systemd/system/service.d/ are not portable across nixpkgs versions).
        systemd = {
          services = {
            btrfs-scrub = {
              description = "Btrfs scrub";
              serviceConfig = {
                Type = "oneshot";
                IOSchedulingClass = "idle";
                ExecStart = "${pkgs.btrfs-progs}/bin/btrfs scrub start -B /";
                Nice = 19;
              };
              unitConfig.OnFailure = "ntfy-failure@%N.service";
            };
            "ntfy-failure@" = {
              description = "ntfy OnFailure notification for %i";
              serviceConfig = {
                Type = "oneshot";
                # %i is expanded by systemd at runtime, so it MUST be outside the
                # writeShellScript store path (systemd does not expand specifiers
                # inside executed files).  Pass it as argument $1.
                ExecStart = "${pkgs.writeShellScript "ntfy-failure" ''
                  set -euo pipefail
                  SERVICE="$1"

                  # Self-guard: if WE are the failing unit, stop — no recursion.
                  case "$SERVICE" in
                    ntfy-failure*) exit 0 ;;
                  esac

                  TOKEN=$(cat ${config.age.secrets.ntfy-token.path})
                  TOPIC=$(cat ${config.age.secrets.ntfy-topic.path})
                  curl -sS -o /dev/null \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "Title: ${config.networking.hostName} unit failed" \
                    -d "$SERVICE failed on ${config.networking.hostName} — check journalctl -u $SERVICE" \
                    "$TOPIC"
                ''} %i";
              };
            };
            free-space-check = {
              description = "Free-space check with ntfy alert";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "free-space-check" ''
                  set -euo pipefail
                  THRESHOLD=${toString cfg.freeSpaceThreshold}

                  # btrfs filesystem usage -b gives byte-precise values.
                  # df is misleading on Btrfs, so compute used % from device
                  # size and Used bytes.
                  USED_PCT=$( \
                    ${pkgs.btrfs-progs}/bin/btrfs filesystem usage -b / \
                    | ${pkgs.gawk}/bin/awk '
                      /Device size/   { total = $NF }
                      /^[[:space:]]+Used:[[:space:]]/ { used = $NF }
                      END { if (total > 0) printf "%.0f", (used / total) * 100; else print "0" }
                    ' )

                  if [ -z "$USED_PCT" ]; then
                    echo "free-space-check: could not parse btrfs usage" >&2
                    exit 1
                  fi

                  # Export a Btrfs-aware Prometheus metric so Grafana alerts on the
                  # same signal as the ntfy check, not df-style filesystem stats.
                  mkdir -p /var/lib/prometheus/textfiles
                  host="${config.networking.hostName}"
                  printf '%s\n' '# HELP btrfs_usage_percent Percent of Btrfs device space currently used.' '# TYPE btrfs_usage_percent gauge' "btrfs_usage_percent{host=\"$host\"} $USED_PCT" '# HELP btrfs_usage_threshold_percent Configured Btrfs usage alert threshold.' '# TYPE btrfs_usage_threshold_percent gauge' "btrfs_usage_threshold_percent{host=\"$host\"} $THRESHOLD" > /var/lib/prometheus/textfiles/btrfs-space.prom.$$
                  mv /var/lib/prometheus/textfiles/btrfs-space.prom.$$ /var/lib/prometheus/textfiles/btrfs-space.prom

                  if [ "$USED_PCT" -gt "$THRESHOLD" ]; then
                    TOKEN=$(cat ${config.age.secrets.ntfy-token.path})
                    TOPIC=$(cat ${config.age.secrets.ntfy-topic.path})
                    curl -sS -o /dev/null \
                      -H "Authorization: Bearer $TOKEN" \
                      -H "Title: ${config.networking.hostName} low disk space" \
                      -H "Tags: warning" \
                      -d "Disk usage at $USED_PCT% (threshold: $THRESHOLD%). Check btrfs filesystem usage." \
                      "$TOPIC"
                  fi
                '';
              };
            };
          };
          timers = {
            btrfs-scrub = {
              description = "Monthly Btrfs scrub";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "monthly";
                RandomizedDelaySec = "1h";
                Persistent = true;
              };
            };
            free-space-check = {
              description = "Hourly free-space check";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "hourly";
                RandomizedDelaySec = "120";
                Persistent = true;
              };
            };
          };
        };
      };
    };
}
