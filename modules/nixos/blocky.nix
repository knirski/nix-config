{
  aspects.nixos.blocky =
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
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      };

      config = lib.mkIf cfg.enable {
        services.blocky = {
          enable = true;
          inherit (cfg) settings;
        };

        systemd.services.blocky = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        # systemd-resolved handles split DNS between Blocky and Tailscale.
        # Blocky on 127.0.0.1:53 serves .home.arpa (local LAN records from
        # reservations.nix), while Tailscale MagicDNS on 100.100.100.100
        # serves *.danio-cloud.ts.net via its own per-link configuration on
        # the tailscale0 interface. resolved routes each domain to the right
        # upstream automatically — no manual /etc/hosts or hardcoded IPs.
        # Previously this was disabled with resolvconf, but Tailscale's
        # resolvconf override hid Blocky from the system resolver entirely.
        # Docs: https://wiki.archlinux.org/title/Systemd-resolved
        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNS = "127.0.0.1";
          };
        };
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
