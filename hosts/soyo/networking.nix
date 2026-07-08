{
  config,
  ...
}:
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

  # Tailscale: secure mesh VPN for remote admin. Authenticates automatically
  # using the agenix-encrypted auth key. Advertises routes so the whole
  # 10.0.0.0/24 LAN is reachable via Tailscale.
  services.tailscaleAutoconnect = {
    enable = true;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
    extraArgs = [ "--advertise-routes=10.0.0.0/24" ];
  };
}
