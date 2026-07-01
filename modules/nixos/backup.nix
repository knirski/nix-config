{
  flake.modules.nixos.backup =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.backup;
    in
    {
      options.lanAppliance.services.backup = {
        enable = lib.mkEnableOption "restic off-host backups to the Synology and btrbk local snapshots";
        restic = {
          repository = lib.mkOption {
            type = lib.types.str;
            example = "sftp:soyo-backup@nas.home.arpa:/backup/soyo";
          };
          passwordFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to the restic repository password file (agenix secret path).";
          };
          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            example = [ "/persist" ];
          };
          exclude = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "/persist/var/log/*"
              "/persist/home/*/.bash_history"
              "/persist/home/*/.local/share/direnv/*"
            ];
            description = "Patterns to exclude from backup. Default excludes logs, bash history, and direnv caches — no recovery value.";
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
          };
          pruneOpts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 6"
              "--keep-yearly 2"
            ];
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
            description = "Btrbk subvolumes under / to snapshot. Snapshot dir must be on a different subvolume than the source.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        # Off-host backups to the Synology DS423+ via restic (SFTP transport).
        # Repo password is an agenix secret; prune retention follows a 3-2-1
        # intent — local snapshots for quick mistakes, restic for real disaster.
        services.restic.backups.soyo = {
          initialize = true;
          repository = cfg.restic.repository;
          passwordFile = cfg.restic.passwordFile;
          paths = cfg.restic.paths;
          exclude = cfg.restic.exclude;
          timerConfig = cfg.restic.timerConfig;
          extraBackupArgs = [
            "--tag"
            "soyo"
          ];
          extraOptions =
            cfg.restic.extraOptions
            ++ lib.optionals (cfg.restic.sshKeyFile != null) [
              "sftp.command=ssh soyo-backup@czworaczki -i ${cfg.restic.sshKeyFile} -s sftp"
            ];
          pruneOpts = cfg.restic.pruneOpts;
          checkOpts = cfg.restic.checkOpts;

          # Record start time for tracing, then push an OTLP trace after completion.
          # Traces show duration, phases, and success/failure in Tempo.
          backupPrepareCommand = ''
            date +%s%N > /run/restic-backup-start
          '';
          backupCleanupCommand = ''
                        START_NS=$(cat /run/restic-backup-start 2>/dev/null || echo "0")
                        END_NS=$(date +%s%N)
                        RESULT="''${SERVICE_RESULT:-unknown}"
                        STATUS="''${EXIT_STATUS:-0}"

                        # Push OTLP trace to Tempo via Alloy
                        ${pkgs.python3}/bin/python3 -c "
            import json, os, uuid, subprocess
            start = int(os.environ.get('START_NS', '0'))
            end = int(os.environ.get('END_NS', '0'))
            if start <= 0:
                start = end - 120_000_000_000  # assume 2 min if no start recorded
            result = os.environ.get('RESULT', 'unknown')
            status = os.environ.get('STATUS', '0')
            trace_id = uuid.uuid4().hex
            root_id = uuid.uuid4().hex[:16]
            spans = [{
                'traceId': trace_id, 'spanId': root_id,
                'name': 'restic-backup', 'kind': 2,
                'startTimeUnixNano': str(start), 'endTimeUnixNano': str(end),
                'status': {'code': 1 if result != 'success' else 0},
                'attributes': [
                    {'key': 'service.name', 'value': {'stringValue': 'restic-backup'}},
                    {'key': 'result', 'value': {'stringValue': result}},
                    {'key': 'exit_status', 'value': {'stringValue': status}}
                ]
            }]
            trace = {
                'resourceSpans': [{
                    'resource': {'attributes': [
                        {'key': 'service.name', 'value': {'stringValue': 'restic-backup'}},
                        {'key': 'host.name', 'value': {'stringValue': 'soyo'}}
                    ]},
                    'scopeSpans': [{'scope': {'name': 'restic'}, 'spans': spans}]
                }]
            }
            subprocess.run(['curl', '-sS', '-o', '/dev/null', '-X', 'POST',
                '-H', 'Content-Type: application/json',
                '--data', json.dumps(trace),
                'http://127.0.0.1:4318/v1/traces'], timeout=10, capture_output=True)
            " 2>/dev/null || true

                        # Write Prometheus textfile metric for alerting
                        mkdir -p /var/lib/prometheus/textfiles
                        if [ "$RESULT" = "success" ]; then
                          cat > /var/lib/prometheus/textfiles/backup.prom.$$ << EOF
            # HELP restic_backup_success 1 if last backup succeeded, 0 otherwise
            # TYPE restic_backup_success gauge
            restic_backup_success 1
            EOF
                        else
                          cat > /var/lib/prometheus/textfiles/backup.prom.$$ << EOF
            # HELP restic_backup_success 1 if last backup succeeded, 0 otherwise
            # TYPE restic_backup_success gauge
            restic_backup_success 0
            EOF
                        fi
                        mv /var/lib/prometheus/textfiles/backup.prom.$$ /var/lib/prometheus/textfiles/backup.prom

                        # ntfy notification on failure (unchanged)
                        if [ "$RESULT" != "success" ]; then
                          TOKEN=$(cat ${config.age.secrets.ntfy-token.path} 2>/dev/null || echo "")
                          TOPIC=$(cat ${config.age.secrets.ntfy-topic.path} 2>/dev/null || echo "")
                          if [ -n "$TOKEN" ] && [ -n "$TOPIC" ]; then
                            curl -sS -o /dev/null \
                              -H "Authorization: Bearer $TOKEN" \
                              -H "Title: soyo backup failed" \
                              -H "Tags: error" \
                              -d "restic backup to Synology failed: $RESULT (exit $STATUS) — check 'journalctl -u restic-backups-soyo -n 30'" \
                              "$TOPIC"
                          fi
                        fi
          '';
        };

        # Local Btrfs snapshots via the first-class btrbk module.
        # Snapshots land in /snapshots (a separate subvolume from / and /persist
        # so snapshot creation is a reflink copy, not a recursive copy).
        services.btrbk = {
          instances.soyo = {
            onCalendar = "daily";
            settings = {
              timestamp_format = "long";
              volume."/" = {
                subvolume = lib.listToAttrs (
                  map (vol: {
                    name = vol.name;
                    value = {
                      snapshot_dir = vol.snapshotDir;
                      snapshot_create = "always";
                    }
                    // lib.optionalAttrs (vol.retention != { }) {
                      snapshot_preserve_min = "2d";
                    }
                    // lib.listToAttrs (
                      lib.mapAttrsToList (k: v: lib.nameValuePair "snapshot_preserve_${k}" (toString v)) vol.retention
                    );
                  }) cfg.btrbk.subvolumes
                );
              };
            };
          };
        };
      };
    };
}
