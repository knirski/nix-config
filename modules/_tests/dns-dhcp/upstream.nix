# Hermetic authoritative-ish upstream for the DNS/DHCP VM test.
#
# dnsmasq is deliberately sufficient here: the resilience test needs a local
# DNS peer whose availability it can control, not another recursive resolver.
{ pkgs, ... }:
{
  virtualisation.vlans = [ 2 ];
  networking = {
    useDHCP = false;
    interfaces.eth1.ipv4.addresses = [
      {
        address = "192.0.2.53";
        prefixLength = 24;
      }
    ];
    firewall.allowedUDPPorts = [ 53 ];
    firewall.allowedTCPPorts = [ 53 ];
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      no-resolv = true;
      no-hosts = true;
      listen-address = "192.0.2.53";
      bind-interfaces = true;
      # Authoritative mode gives deterministic NXDOMAIN for names not listed
      # in this private fixture zone; it never falls through to public DNS.
      auth-server = "fixture.example.net,eth1";
      auth-zone = "fixture.example.net";
      host-record = [
        "cached.fixture.example.net,192.0.2.10"
        "outage.fixture.example.net,192.0.2.11"
        "recovered.fixture.example.net,192.0.2.12"
      ];
    };
  };

  environment.systemPackages = [
    pkgs.dnsutils
    pkgs.iproute2
  ];
}
