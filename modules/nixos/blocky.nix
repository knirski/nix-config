{
  flake.modules.nixos.blocky =
    { lib, config, ... }:
    let
      cfg = config.soyo.services.blocky;
    in
    {
      options.soyo.services.blocky = {
        enable = lib.mkEnableOption "Blocky DNS";
        metricsInterface = lib.mkOption { type = lib.types.str; };
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

        services.resolved.enable = false;
        networking.firewall.allowedTCPPorts = [ 53 ];
        networking.firewall.allowedUDPPorts = [ 53 ];
        networking.firewall.interfaces.${cfg.metricsInterface}.allowedTCPPorts = [ 4000 ];
      };
    };
}
