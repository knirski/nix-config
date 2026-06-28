{
  flake.modules.nixos.remote-unlock =
    { lib, config, ... }:
    let
      cfg = config.soyo.services.remoteUnlock;
    in
    {
      options.soyo.services.remoteUnlock = {
        enable = lib.mkEnableOption "systemd-initrd remote unlock";
        interface = lib.mkOption { type = lib.types.str; };
        lanAddress = lib.mkOption { type = lib.types.str; };
        rescueAddress = lib.mkOption { type = lib.types.str; };
        gatewayAddress = lib.mkOption { type = lib.types.str; };
        sshHostKeys = lib.mkOption { type = lib.types.listOf lib.types.str; };
        authorizedKeys = lib.mkOption { type = lib.types.listOf lib.types.str; };
      };

      config = lib.mkIf cfg.enable {
        boot.initrd.network.enable = true;
        boot.initrd.network.ssh = {
          enable = true;
          port = 2222;
          hostKeys = cfg.sshHostKeys;
          authorizedKeys = cfg.authorizedKeys;
        };
        # The initrd SSH host key lives unencrypted on the ESP (it must be
        # available before LUKS unlock); keep a stable fingerprint across rebuilds.
        systemd.tmpfiles.rules = [ "d /boot/initrd-ssh 0700 root root -" ];

        boot.initrd.systemd.network.networks."10-${cfg.interface}" = {
          matchConfig.Name = cfg.interface;
          address = [
            cfg.lanAddress
            cfg.rescueAddress
          ];
          routes = [ { Gateway = cfg.gatewayAddress; } ];
        };
      };
    };
}
