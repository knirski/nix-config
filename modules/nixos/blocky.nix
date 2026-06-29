{
  flake.modules.nixos.blocky =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.blocky;
    in
    {
      options.lanAppliance.services.blocky = {
        enable = lib.mkEnableOption "Blocky DNS";
        lanInterface = lib.mkOption { type = lib.types.str; };
        # The rich policy stays host-local; the shared aspect owns service wiring.
        settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };

      config = lib.mkIf cfg.enable {
        services.blocky = {
          enable = true;
          settings = cfg.settings;
        };

        systemd.services.blocky = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        services.resolved.enable = false;
        networking.nameservers = [ "127.0.0.1" ];
        networking.firewall.interfaces.${cfg.lanInterface} = {
          allowedTCPPorts = [
            53
            4000
          ];
          allowedUDPPorts = [ 53 ];
        };
      };
    };
}
