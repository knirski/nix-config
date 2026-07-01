{
  networking.useDHCP = false;

  systemd.network.networks."10-enp1s0" = {
    matchConfig.Name = "enp1s0";
    address = [ "10.0.0.9/24" ];
    routes = [ { Gateway = "10.0.0.1"; } ];
    networkConfig = {
      DNS = "127.0.0.1";
      Domains = [ "home.arpa" ];
    };
  };

  networking.firewall.enable = true;

  # Tailscale: secure mesh VPN for remote admin. After deploy, authenticate:
  #   sudo tailscale up
  # Or set lanAppliance.services.tailscale.authKeyFile for unattended setup.
  lanAppliance.services.tailscale.enable = true;
}
