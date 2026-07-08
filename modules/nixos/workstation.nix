{
  aspects.nixos.workstation =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (config.networking) hostName;
      tsCfg = config.workstation.services.tailscale;
      bkCfg = config.workstation.services.backup;
    in
    {
      options.workstation.services.tailscale = {
        enable = lib.mkEnableOption "Tailscale mesh VPN for remote access";
        authKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to a Tailscale auth key file (agenix secret).";
        };
      };

      options.workstation.services.backup = {
        enable = lib.mkEnableOption "restic off-host backups + btrbk local snapshots";
        restic = {
          repository = lib.mkOption { type = lib.types.str; };
          passwordFile = lib.mkOption { type = lib.types.path; };
          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "/persist" ];
          };
          exclude = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "/persist/var/log/*"
              "/persist/home/*/.bash_history"
              "/persist/home/*/.local/share/direnv/*"
              "*.steam"
            ];
          };
          sshKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          timerConfig = lib.mkOption {
            type = lib.types.attrs;
            default = {
              OnCalendar = "daily";
              Persistent = true;
              RandomizedDelaySec = "2h";
            };
          };
          pruneOpts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 6"
            ];
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
          };
        };
      };

      config = {
        services = {
          # OpenSSH server (key-only)
          openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
              PermitRootLogin = "no";
            };
          };

          # Tailscale
          tailscale = lib.mkIf tsCfg.enable { enable = true; };

          # Backups
          restic.backups.${hostName} = lib.mkIf bkCfg.enable {
            initialize = true;
            repository = bkCfg.restic.repository;
            passwordFile = bkCfg.restic.passwordFile;
            paths = bkCfg.restic.paths;
            exclude = bkCfg.restic.exclude;
            timerConfig = bkCfg.restic.timerConfig;
            extraOptions = lib.optionals (bkCfg.restic.sshKeyFile != null) [
              "sftp.command='ssh ${hostName}-backup@czworaczki.home.arpa -i ${bkCfg.restic.sshKeyFile} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/persist/etc/restic/known_hosts -s sftp'"
            ];
            pruneOpts = bkCfg.restic.pruneOpts;
            extraBackupArgs = [
              "--tag"
              hostName
            ];
          };

          btrbk = lib.mkIf (bkCfg.enable && bkCfg.btrbk.subvolumes != [ ]) {
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
                      }
                      // lib.listToAttrs (
                        lib.mapAttrsToList (k: v: lib.nameValuePair "snapshot_preserve_${k}" (toString v)) vol.retention
                      );
                    }) bkCfg.btrbk.subvolumes
                  );
                };
              };
            };
          };
        };

        # Tailscale auth oneshot
        systemd.services.tailscale-auth = lib.mkIf (tsCfg.enable && tsCfg.authKeyFile != null) {
          description = "Authenticate Tailscale with auth key";
          after = [
            "tailscale.service"
            "agenix-activation.service"
          ];
          wants = [ "tailscale.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "tailscale-auth" ''
              if ! ${pkgs.tailscale}/bin/tailscale status 2>/dev/null | grep -qE '^\d+\.\d+\.\d+\.\d+\s'; then
                ${pkgs.tailscale}/bin/tailscale up --auth-key "$(cat ${tsCfg.authKeyFile})"
              fi
            '';
            MemoryMax = "32M";
            CPUQuota = "10%";
          };
        };
      };
    };
}
