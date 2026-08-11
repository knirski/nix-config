{
  config,
  ...
}:
{
  networking = {
    useDHCP = false;

    firewall.enable = true;

    # Use the nftables firewall backend rather than the default iptables one.
    # The default backend implements checkReversePath (NixOS default: true)
    # with the iptables-nft rpfilter match (ipt_rpfilter over nft_compat), which
    # runs on every received packet in softirq context. On 2026-08-11 that match
    # soft-locked the kernel — ksoftirqd/0 stuck in rpfilter_lookup_reverse
    # after the onboard NIC's adapter-reset storm — until the appliance was
    # completely hung and needed a cold restart. The nftables backend keeps
    # strict reverse-path filtering but implements it natively with `fib`, so
    # no xtables-compat match code runs in the receive path at all.
    nftables.enable = true;
  };

  systemd.network.networks."10-enp1s0" = {
    matchConfig.Name = "enp1s0";
    address = [ "10.0.0.9/24" ];
    routes = [ { Gateway = "10.0.0.1"; } ];
    networkConfig = {
      DNS = "127.0.0.1";
      Domains = [ "home.arpa" ];
    };
  };

  # Tailscale: secure mesh VPN for remote admin. Authenticates automatically
  # using the agenix-encrypted auth key. Advertises routes so the whole
  # 10.0.0.0/24 LAN is reachable via Tailscale.
  lanAppliance.services.tailscale = {
    enable = true;
    isolateResources = true;
    nice = 10;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
    extraArgs = [ "--advertise-routes=10.0.0.0/24" ];
  };
}
