{ config, ... }:
{
  lanAppliance.services.backup = {
    enable = true;
    # No explicit hostName — defaults to config.networking.hostName = "zbook"
    enablePromMetrics = true;
    isolateResources = true;

    restic = {
      repository = "sftp:zbook-backup@czworaczki:/backup/zbook";
      passwordFile = config.age.secrets.zbook-restic-password.path;
      paths = [
        "/persist"
      ];
      sshKeyFile = "/persist/etc/restic/ssh-key";

      sftp = {
        # Same NAS as Soyo; the FQDN routes through Blocky (LAN DNS) instead
        # of matching Tailscale's per-link domain.
        host = "czworaczki.home.arpa";
        user = "zbook-backup";
      };

      pruneOpts = [
        "--keep-daily"
        "7"
        "--keep-weekly"
        "4"
        "--keep-monthly"
        "6"
      ];

      checkOpts = [ "--with-cache" ];
    };

    btrbk.subvolumes = [
      {
        name = "persist";
        snapshotDir = "/snapshots/persist";
        retention = {
          daily = 7;
          weekly = 4;
          monthly = 3;
        };
      }
    ];
  };
}
