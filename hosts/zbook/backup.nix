{ config, ... }:
{
  services.backup = {
    enable = true;
    # No explicit hostName — defaults to config.networking.hostName = "zbook"

    restic = {
      repository = "sftp:zbook-backup@czworaczki:/backup/zbook";
      passwordFile = config.age.secrets.zbook-restic-password.path;
      paths = [
        "/persist"
      ];
      sshKeyFile = "/persist/etc/restic/ssh-key";
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
