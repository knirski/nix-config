# Unified backup aspect: restic off-host backup + btrbk local snapshots.
#
# Used by both Soyo (appliance) and zbook (workstation). Host-specific
# config lives in hosts/<name>/backup.nix. Advanced features (OTLP tracing,
# Prometheus backup metrics) are opt-in — Soyo enables both, zbook uses
# defaults (neither).
{
  aspects.nixos.backup =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.backup;
      hostName = if cfg.hostName != null then cfg.hostName else config.networking.hostName;
      hardening = import ../../lib/systemd-hardening.nix;
    in
    {
      options.lanAppliance.services.backup = {
        enable = lib.mkEnableOption "restic off-host backups + btrbk local snapshots";

        hostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Host name for restic backup name and SFTP user. Defaults to config.networking.hostName.";
        };

        enableTracing = lib.mkEnableOption "OTLP tracing of backup runs to local Tempo";
        enablePromMetrics = lib.mkEnableOption "Prometheus textfile metrics for backup success/ran status";
        isolateResources = lib.mkEnableOption "resource limits for backup units on a role-constrained host";
        notifyOnFailure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Wire OnFailure = ntfy-failure@%N.service so backup failures send a push notification via the maintenance aspect's ntfy-failure@ template. If the maintenance aspect is not enabled, systemd logs a warning on failure but the backup service itself is unaffected.";
        };

        restic = {
          repository = lib.mkOption {
            type = lib.types.str;
            example = "sftp:soyo-backup@nas.home.arpa:/backup/soyo";
            description = "Restic repository URL (SFTP target).";
          };
          passwordFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to the restic repository password file (agenix secret).";
          };
          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "/persist" ];
            description = "Paths to back up.";
          };
          exclude = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "/persist/var/log/*"
              "/persist/home/*/.bash_history"
              "/persist/home/*/.local/share/direnv/*"
            ];
            description = "Patterns to exclude — logs, bash history, and direnv caches have no recovery value.";
          };
          sshKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to an SSH private key for SFTP transport. Persist this under /persist/etc/restic/ so it survives reboots.";
          };
          extraOptions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional -o options passed to restic. The sshKeyFile option auto-generates the sftp.command value when set.";
          };
          timerConfig = lib.mkOption {
            type = lib.types.attrs;
            default = {
              OnCalendar = "daily";
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
            description = "systemd timer config for the restic backup service.";
          };
          pruneOpts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 6"
            ];
            description = "Prune options. Default: 7 daily, 4 weekly, 6 monthly. Override for yearly retention.";
          };
          checkOpts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "--with-cache" ];
            description = "Options for 'restic check' run after each backup. Empty = no check.";
          };
        };

        btrbk = {
          subvolumes = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption { type = lib.types.str; };
                  snapshotDir = lib.mkOption { type = lib.types.str; };
                  retention = lib.mkOption {
                    type = lib.types.attrsOf (lib.types.either lib.types.int lib.types.str);
                    default = { };
                  };
                };
              }
            );
            default = [ ];
            description = "Btrbk subvolumes under / to snapshot. Snapshot dir must be on a different subvolume than the source.";
          };
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          # Prometheus backup metric bootstrap (optional)
          (lib.mkIf cfg.enablePromMetrics {
            systemd.services.restic-backup-metric-bootstrap = {
              description = "Seed restic backup alert metrics before the first backup run";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = hardening.offline // {
                Type = "oneshot";
                ExecStart = lib.getExe (
                  pkgs.writeShellApplication {
                    name = "restic-backup-metric-bootstrap";
                    runtimeInputs = [ pkgs.coreutils ];
                    text = ''
                      set -euo pipefail
                      mkdir -p /var/lib/prometheus/textfiles
                      if [ -e /var/lib/prometheus/textfiles/backup.prom ]; then
                        exit 0
                      fi

                      printf '%s\n' \
                        '# HELP restic_backup_ran 1 after the first backup attempt completes, 0 before that.' \
                        '# TYPE restic_backup_ran gauge' \
                        'restic_backup_ran 0' \
                        '# HELP restic_backup_success 1 if the last completed backup succeeded, 0 otherwise.' \
                        '# TYPE restic_backup_success gauge' \
                        'restic_backup_success 1' \
                        > /var/lib/prometheus/textfiles/backup.prom
                    '';
                  }
                );
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 10;
                ReadWritePaths = [ "/var/lib/prometheus/textfiles" ];
                TimeoutStartSec = "30s";
                Restart = "no";
              };
            };
          })

          # Main restic backup config
          {
            services.restic.backups.${hostName} = {
              initialize = true;
              repository = cfg.restic.repository;
              passwordFile = cfg.restic.passwordFile;
              paths = cfg.restic.paths;
              exclude = cfg.restic.exclude;
              timerConfig = cfg.restic.timerConfig;
              extraBackupArgs = [
                "--tag"
                hostName
              ];
              extraOptions =
                cfg.restic.extraOptions
                ++ lib.optionals (cfg.restic.sshKeyFile != null) [
                  # Single quotes around the SSH command are required — systemd's
                  # ExecStart= parser splits on spaces, and without them sftp.command
                  # would only be set to "ssh" while the host and key path would leak
                  # as separate positional arguments to restic.
                  # StrictHostKeyChecking=accept-new avoids the interactive prompt on
                  # first connection; UserKnownHostsFile persists the host key under
                  # /persist (the root filesystem is ephemeral on this host).
                  # The FQDN czworaczki.home.arpa routes to Blocky (LAN DNS) instead
                  # of matching Tailscale's per-link domain.
                  "sftp.command='ssh ${hostName}-backup@czworaczki.home.arpa -i ${cfg.restic.sshKeyFile} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/persist/etc/restic/known_hosts -s sftp'"
                ];
              pruneOpts = cfg.restic.pruneOpts;
              checkOpts = cfg.restic.checkOpts;
            }
            # Conditionally add tracing prepare/cleanup commands
            // lib.optionalAttrs cfg.enableTracing {
              backupPrepareCommand = ''
                date +%s%N > /run/restic-backup-start
              '';
              backupCleanupCommand = ''
                START_NS=$(cat /run/restic-backup-start 2>/dev/null || echo "0")
                END_NS=$(date +%s%N)
                RESULT="''${SERVICE_RESULT:-unknown}"
                TRACE_ID=$(${pkgs.util-linux}/bin/uuidgen | tr -d -)
                SPAN_ID=$(${pkgs.util-linux}/bin/uuidgen | tr -d - | cut -c1-16)
                OK=0; [ "$RESULT" = "success" ] || OK=1
                ${pkgs.jq}/bin/jq -nc \
                  --arg trace_id "$TRACE_ID" \
                  --arg span_id "$SPAN_ID" \
                  --arg start_ns "$START_NS" \
                  --arg end_ns "$END_NS" \
                  --arg result "$RESULT" \
                  --argjson ok "$OK" \
                  '{
                    resourceSpans: [{
                      resource: {attributes: [
                        {key: "service.name", value: {stringValue: "restic-backup"}},
                        {key: "host.name", value: {stringValue: "${hostName}"}}
                      ]},
                      scopeSpans: [{
                        scope: {name: "restic"},
                        spans: [{
                          traceId: $trace_id, spanId: $span_id,
                          name: "restic-backup", kind: 2,
                          startTimeUnixNano: $start_ns,
                          endTimeUnixNano: $end_ns,
                          status: {code: $ok},
                          attributes: [
                            {key: "result", value: {stringValue: $result}}
                          ]
                        }]
                      }]
                    }]
                  }' \
                  | ${pkgs.curl}/bin/curl -sS -o /dev/null -X POST \
                    -H 'Content-Type: application/json' \
                    -d @- http://localhost:4318/v1/traces || true
                ${lib.optionalString cfg.enablePromMetrics ''
                  mkdir -p /var/lib/prometheus/textfiles
                  if [ "$RESULT" = "success" ]; then
                    printf '%s\n' '# HELP restic_backup_ran 1 after the first backup attempt completes, 0 before that.' '# TYPE restic_backup_ran gauge' 'restic_backup_ran 1' '# HELP restic_backup_success 1 if last backup succeeded, 0 otherwise' '# TYPE restic_backup_success gauge' 'restic_backup_success 1' > /var/lib/prometheus/textfiles/backup.prom.$$
                  else
                    printf '%s\n' '# HELP restic_backup_ran 1 after the first backup attempt completes, 0 before that.' '# TYPE restic_backup_ran gauge' 'restic_backup_ran 1' '# HELP restic_backup_success 1 if last backup succeeded, 0 otherwise' '# TYPE restic_backup_success gauge' 'restic_backup_success 0' > /var/lib/prometheus/textfiles/backup.prom.$$
                  fi
                  mv /var/lib/prometheus/textfiles/backup.prom.$$ /var/lib/prometheus/textfiles/backup.prom
                ''}
              '';
            }
            // lib.optionalAttrs (cfg.enablePromMetrics && !cfg.enableTracing) {
              # Prometheus metrics without tracing — no prepare step needed.
              backupCleanupCommand = ''
                RESULT="''${SERVICE_RESULT:-unknown}"
                mkdir -p /var/lib/prometheus/textfiles
                if [ "$RESULT" = "success" ]; then
                  printf '%s\n' '# HELP restic_backup_ran 1 after the first backup attempt completes, 0 before that.' '# TYPE restic_backup_ran gauge' 'restic_backup_ran 1' '# HELP restic_backup_success 1 if last backup succeeded, 0 otherwise' '# TYPE restic_backup_success gauge' 'restic_backup_success 1' > /var/lib/prometheus/textfiles/backup.prom.$$
                else
                  printf '%s\n' '# HELP restic_backup_ran 1 after the first backup attempt completes, 0 before that.' '# TYPE restic_backup_ran gauge' 'restic_backup_ran 1' '# HELP restic_backup_success 1 if last backup succeeded, 0 otherwise' '# TYPE restic_backup_success gauge' 'restic_backup_success 0' > /var/lib/prometheus/textfiles/backup.prom.$$
                fi
                mv /var/lib/prometheus/textfiles/backup.prom.$$ /var/lib/prometheus/textfiles/backup.prom
              '';
            };

            # Backups are deliberately subordinate to the host's primary role.
            # The cap is large enough for restic's index while preventing an
            # unusually large repository operation from exhausting Soyo.
            systemd.services."restic-backups-${hostName}" = {
              serviceConfig = lib.mkIf cfg.isolateResources {
                MemoryMax = "1G";
                CPUQuota = "50%";
                Nice = 10;
                IOWeight = 25;
              };
              unitConfig.OnFailure = lib.mkIf cfg.notifyOnFailure "ntfy-failure@%N.service";
            };
          }

          # Local Btrfs snapshots via the first-class btrbk module.
          # Snapshots land in /snapshots (a separate subvolume from / and /persist
          # so snapshot creation is a reflink copy, not a recursive copy).
          (lib.mkIf (cfg.btrbk.subvolumes != [ ]) {
            services.btrbk = {
              instances.${hostName} = {
                onCalendar = "daily";
                settings = {
                  timestamp_format = "long";
                  volume."/" = {
                    subvolume = lib.listToAttrs (
                      map (vol: {
                        inherit (vol) name;
                        value = {
                          snapshot_dir = vol.snapshotDir;
                          snapshot_create = "always";
                        }
                        // lib.optionalAttrs (vol.retention != { }) {
                          snapshot_preserve_min = "2d";
                          snapshot_preserve = lib.concatStringsSep " " (
                            lib.mapAttrsToList (
                              k: v:
                              "${toString v}${
                                {
                                  daily = "d";
                                  weekly = "w";
                                  monthly = "m";
                                  yearly = "y";
                                }
                                .${k}
                              }"
                            ) vol.retention
                          );
                        };
                      }) cfg.btrbk.subvolumes
                    );
                  };
                };
              };
            };
            systemd.services."btrbk-${hostName}".serviceConfig = lib.mkIf cfg.isolateResources {
              MemoryMax = "512M";
              CPUQuota = "25%";
              Nice = 10;
              IOWeight = 25;
            };
          })
        ]
      );
    };
}
