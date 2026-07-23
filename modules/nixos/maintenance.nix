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
      hardening = import ../../lib/systemd-hardening.nix;
      btrfsMetrics = import ../../lib/observability/btrfs-metrics.nix;
      prometheusTextfileDirectory = "/var/lib/prometheus/textfiles";
      prometheusTextfileEnabled = config.services.prometheus.exporters.node.enable;

      # smartd's "-M exec" hook (see the smartd.devices wiring below) runs this
      # with no stdin and no command-line arguments — every fact about the
      # event is passed as an environment variable by smartd itself (see
      # `man 5 smartd.conf`, the "-M exec PATH" Directive). Read the ntfy
      # credentials from the agenix secret files at runtime, same as
      # ntfy-failure@ and free-space-check, so the token/topic are never
      # embedded in the Nix store or visible in `ps`.
      #
      # SMARTD_MESSAGE/SMARTD_DEVICESTRING may contain spaces (the manual
      # explicitly warns they are "NOT quoted" when smartd exports them), so
      # every reference here is inside double quotes. They are placed only in
      # the curl request *body* (-d), never in a header (-H): a header value
      # can't safely carry arbitrary/unsanitized text (e.g. embedded
      # newlines), while curl sends -d content as literal body bytes.
      smartdNotify = pkgs.writeShellApplication {
        name = "ntfy-smartd-notify";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
        ];
        text = ''
          set -euo pipefail

          DEVICE="''${SMARTD_DEVICE:-unknown device}"
          FAILTYPE="''${SMARTD_FAILTYPE:-unknown}"
          MESSAGE="''${SMARTD_MESSAGE:-no message provided}"

          TOKEN=$(cat ${config.age.secrets.ntfy-token.path})
          TOPIC=$(cat ${config.age.secrets.ntfy-topic.path})
          curl -sS --max-time 15 -o /dev/null \
            -H "Authorization: Bearer $TOKEN" \
            -H "Title: ${config.networking.hostName} SMART warning" \
            -H "Tags: warning" \
            -d "SMART warning on $DEVICE ($FAILTYPE) on ${config.networking.hostName} — check smartctl -a $DEVICE. $MESSAGE" \
            "$TOPIC"
        '';
      };
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
              # smartd itself runs no systemd OnFailure edge — it is a single
              # long-running daemon, not a oneshot — so SMART warnings need
              # their own notification path. "-m <nomailer> -M exec PATH" is
              # the mechanism nixpkgs' own services.smartd.notifications.*
              # (mail/wall/x11) compiles down to internally (see
              # <nixpkgs>/nixos/modules/services/monitoring/smartd.nix); using
              # it directly means we do not have to also wire mail or a GUI
              # session just to reach the "-M exec" hook. <nomailer> tells
              # smartd to run the script with no stdin and no argv — every
              # event fact arrives as an environment variable instead, which
              # is what smartdNotify below reads.
              options = "-s (S/../.././02|L/../../7/03) -m <nomailer> -M exec ${lib.getExe smartdNotify}";
            }) cfg.smartdDevices;
          };
        };
        networking.timeServers = cfg.ntpServers;

        # --- ntfy OnFailure: individual service drop-ins ---
        # Set on services defined in this module (global drop-ins via
        # systemd/system/service.d/ are not portable across nixpkgs versions).
        systemd = {
          # free-space-check runs on hosts without the observability aspect
          # too. Create its textfile output directory before systemd builds
          # the service's ReadWritePaths namespace; the script cannot mkdir it
          # after namespace setup has already failed. Leave ownership
          # unchanged when another aspect (such as observability) manages
          # this directory.
          tmpfiles.rules = [
            "d /var/lib/prometheus/textfiles 0755 - - -"
          ];
          services = {
            # nix.gc only sets ExecStart/OnCalendar; nixpkgs' nix-gc.service has
            # no unitConfig of its own, so a plain assignment (no mkForce
            # needed) adds the same crash-notification edge as the units below.
            nix-gc.unitConfig.OnFailure = "ntfy-failure@%N.service";
            btrfs-scrub = {
              description = "Btrfs scrub";
              serviceConfig = {
                Type = "oneshot";
                IOSchedulingClass = "idle";
                ExecStart = "${pkgs.btrfs-progs}/bin/btrfs scrub start -B /";
                MemoryMax = "256M";
                CPUQuota = "25%";
                Nice = 19;
                IOWeight = 10;
              };
              unitConfig.OnFailure = "ntfy-failure@%N.service";
            };
            "ntfy-failure@" = {
              description = "ntfy OnFailure notification for %i";
              unitConfig = {
                StartLimitIntervalSec = "60s";
                StartLimitBurst = 3;
              };
              serviceConfig = hardening.networkClient // {
                Type = "oneshot";
                Restart = "no";
                TimeoutStartSec = "30s";
                MemoryMax = "32M";
                CPUQuota = "10%";
                Nice = 10;
                # %i is expanded by systemd at runtime, so it MUST be outside the
                # application store path (systemd does not expand specifiers
                # inside executed files).  Pass it as argument $1.
                ExecStart = "${
                  lib.getExe (
                    pkgs.writeShellApplication {
                      name = "ntfy-failure";
                      runtimeInputs = [
                        pkgs.coreutils
                        pkgs.curl
                      ];
                      text = ''
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
                      '';
                    }
                  )
                } %i";
              };
            };
            free-space-check = {
              description = "Free-space check with ntfy alert";
              wantedBy = [ "multi-user.target" ];
              # The script's own ntfy push (below) is a threshold alert — it
              # fires when disk usage crosses freeSpaceThreshold. This
              # OnFailure edge is a different, additive concern: it notifies
              # if the *script itself* crashes (e.g. the btrfs usage parse
              # fails and it exits 1) before it ever gets to evaluate the
              # threshold.
              unitConfig.OnFailure = "ntfy-failure@%N.service";
              serviceConfig = hardening.networkClient // {
                Type = "oneshot";
                ReadWritePaths = lib.optional prometheusTextfileEnabled prometheusTextfileDirectory;
                Restart = "no";
                TimeoutStartSec = "1m";
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 10;
                ExecStart = lib.getExe (
                  pkgs.writeShellApplication {
                    name = "free-space-check";
                    runtimeInputs = [
                      pkgs.btrfs-progs
                      pkgs.coreutils
                      pkgs.curl
                      pkgs.gawk
                    ];
                    text = ''
                        set -euo pipefail
                        THRESHOLD=${toString cfg.freeSpaceThreshold}

                      # btrfs filesystem usage -b gives byte-precise values.
                      # df is misleading on Btrfs, so compute used % from device
                      # size and Used bytes.
                        USED_PCT=$( \
                          btrfs filesystem usage -b / \
                          | awk '
                          /Device size/   { total = $NF }
                          /^[[:space:]]+Used:[[:space:]]/ { used = $NF }
                          END { if (total > 0) printf "%.0f", (used / total) * 100; else print "0" }
                          ' )

                        if [ -z "$USED_PCT" ]; then
                          echo "free-space-check: could not parse btrfs usage" >&2
                          exit 1
                        fi

                      ${lib.optionalString prometheusTextfileEnabled ''
                        # Export a Btrfs-aware Prometheus metric so Grafana alerts on the
                        # same signal as the ntfy check, not df-style filesystem stats.
                        # Metric names come from lib/observability/btrfs-metrics.nix, the
                        # single source of truth shared with the Grafana alert rule in
                        # lib/observability/grafana-alert-setup.nix — keep them in sync there,
                        # not by hand here.
                        mkdir -p /var/lib/prometheus/textfiles
                        ${btrfsMetrics.hostLabel}="${config.networking.hostName}"
                        printf '%s\n' '# HELP ${btrfsMetrics.usagePercent} Percent of Btrfs device space currently used.' '# TYPE ${btrfsMetrics.usagePercent} gauge' "${btrfsMetrics.usagePercent}{${btrfsMetrics.hostLabel}=\"${"$" + btrfsMetrics.hostLabel}\"} $USED_PCT" '# HELP ${btrfsMetrics.thresholdPercent} Configured Btrfs usage alert threshold.' '# TYPE ${btrfsMetrics.thresholdPercent} gauge' "${btrfsMetrics.thresholdPercent}{${btrfsMetrics.hostLabel}=\"${"$" + btrfsMetrics.hostLabel}\"} $THRESHOLD" > /var/lib/prometheus/textfiles/btrfs-space.prom.$$
                        mv /var/lib/prometheus/textfiles/btrfs-space.prom.$$ /var/lib/prometheus/textfiles/btrfs-space.prom
                      ''}

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
                  }
                );
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
