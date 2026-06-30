{ config, ... }:
{
  lanAppliance.services.backup = {
    enable = true;

    restic = {
      # Synology DS423+ reachable by hostname (Blocky resolves czworaczki
      # from the reservations.nix forward-A records).
      repository = "sftp:soyo-backup@czworaczki:/backup/soyo";
      passwordFile = config.age.secrets.restic-password.path;
      paths = [
        "/persist"
      ];

      # SSH key for passwordless SFTP. Generate on Soyo after first deploy:
      #   sudo ssh-keygen -t ed25519 -f /persist/etc/restic/ssh-key -N "" -C "soyo-backup@soyo"
      #   sudo cat /persist/etc/restic/ssh-key.pub
      # Then add the public key to the Synology soyo-backup user's authorized_keys.
      sshKeyFile = "/persist/etc/restic/ssh-key";

      # Verify repo integrity monthly (runs after each backup, but with
      # randomized timer most runs skip — an explicit periodic check is better).
      # Currently disabled; enable once the backup is confirmed working:
      # checkOpts = [ "--with-cache" ];
    };

    btrbk.subvolumes = [
      {
        name = "persist";
        snapshotDir = "/snapshots/persist";
        retention = {
          daily = "7d";
          weekly = "4w";
          monthly = "6m";
        };
      }
      {
        name = "root";
        snapshotDir = "/snapshots/root";
        retention = {
          daily = "7d";
          weekly = "4w";
          monthly = "3m";
        };
      }
    ];
  };
}
