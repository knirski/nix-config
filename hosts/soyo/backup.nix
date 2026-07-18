{ config, ... }:
{
  lanAppliance.services.backup = {
    enable = true;
    hostName = "soyo";
    enableTracing = true;
    enablePromMetrics = true;
    isolateResources = true;

    restic = {
      # Synology DS423+ reachable by hostname (Blocky resolves czworaczki
      # from the reservations.nix forward-A records).
      repository = "sftp:soyo-backup@czworaczki:/backup/soyo";
      passwordFile = config.age.secrets.restic-password.path;
      # Back up the whole persisted state tree. This includes /persist/var/lib/sbctl,
      # so the Secure Boot signing keys survive a disaster restore too.
      paths = [
        "/persist"
      ];

      # SSH key for passwordless SFTP. Generate on Soyo after first deploy:
      #   sudo ssh-keygen -t ed25519 -f /persist/etc/restic/ssh-key -N "" -C "soyo-backup@soyo"
      #   sudo cat /persist/etc/restic/ssh-key.pub
      # Then add the public key to the Synology soyo-backup user's authorized_keys.
      sshKeyFile = "/persist/etc/restic/ssh-key";

      # Keep yearly retention for the server (backups are critical).
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
        "--keep-yearly 2"
      ];

      # Verify repo integrity monthly (runs after each backup, but with
      # randomized timer most runs skip — an explicit periodic check is better).
      checkOpts = [ "--with-cache" ];
    };

    btrbk.subvolumes = [
      {
        name = "persist";
        snapshotDir = "/snapshots/persist";
        retention = {
          daily = 7;
          weekly = 4;
          monthly = 6;
        };
      }
    ];
  };
}
