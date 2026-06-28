# hosts/soyo/dns.nix
#
# Blocky: client-facing DNS on :53, a forwarding/caching resolver with blocking.
#   - general ad/tracker/malware blocking comes from the encrypted DNS4EU NoAds
#     upstream (they maintain it -> low maintenance for us)
#   - Polish-specific blocking comes from one local, auto-refreshing list
#     (Blocky re-downloads every 24h -> no manual upkeep); it applies to every
#     answer, including failover, so Polish blocking never drops
#   - forward A records are generated from reservations.nix (single source);
#     reverse/PTR is dnsmasq's job (Blocky forwards the reverse zone to it)
#
# M1 wires this policy through modules/nixos/blocky.nix.
#
# Docs: https://0xerr0r.github.io/blocky/ | https://www.joindns4.eu/
#       https://search.nixos.org/options?query=services.blocky

{ lib, ... }:

let
  reservations = import ./reservations.nix;
  # Group IPs by hostname so a multihomed host (e.g. czworaczki, two active
  # interfaces) resolves to all its IPs (Blocky customDNS takes comma-separated
  # values -> multi-A). Map both <name> and <name>.home.arpa.
  names = lib.unique (map (r: r.name) reservations);
  ipsFor = n: lib.concatStringsSep "," (map (r: r.ip) (lib.filter (r: r.name == n) reservations));
  hostMappings = lib.listToAttrs (
    lib.concatMap (n: [
      (lib.nameValuePair n (ipsFor n))
      (lib.nameValuePair "${n}.home.arpa" (ipsFor n))
    ]) names
  );
in
{
  soyo.services.blocky = {
    enable = true;
    metricsInterface = "enp1s0";
    settings = {
      ports = {
        dns = 53;
        http = "10.0.0.9:4000"; # metrics/dashboard, LAN interface only
      };

      # Encrypted (DoH) upstreams only, to keep queries private from the ISP.
      # DNS4EU NoAds filters general ads/trackers/malware upstream; Quad9 is a
      # privacy-respecting encrypted fallback (malware-filtering, no ads) — the
      # local Polish list still applies to every answer regardless of upstream.
      upstreams = {
        groups.default = [
          "https://noads.joindns4.eu/dns-query"
          "https://dns.quad9.net/dns-query"
        ];
        timeout = "2s";
      };

      # Static-IP bootstrap so the DoH hostnames and blocklist URLs resolve at
      # boot, before any name resolution exists.
      bootstrapDns = [
        {
          upstream = "https://noads.joindns4.eu/dns-query";
          ips = [
            "86.54.11.13"
            "86.54.11.213"
          ];
        }
        {
          upstream = "https://dns.quad9.net/dns-query";
          ips = [
            "9.9.9.9"
            "149.112.112.112"
          ];
        }
      ];

      customDNS = {
        customTTL = "1h";
        filterUnmappedTypes = true;
        mapping = hostMappings;
      };

      conditional.mapping = {
        # NoAds may block these Huawei test domains; route around it via the
        # non-ad-filtering encrypted fallback.
        "hwcloudtest.cn" = "https://dns.quad9.net/dns-query";
        # LAN reverse zone -> dnsmasq, which owns lease-aware PTR.
        "0.0.10.in-addr.arpa" = "127.0.0.1:5353";
      };

      blocking = {
        denylists = {
          # Polish-specific ads/trackers; auto-refreshed, no manual upkeep.
          pl = [
            "https://blocklist.sefinek.net/generated/v1/127.0.0.1/other/polish-blocklists/MajkiIT/hostfile.fork.txt"
          ];
          # Disable browser DoH that would bypass this resolver. The Firefox
          # canary makes Firefox fall back to system DNS. (Inline list.)
          doh-bypass = [
            ''
              use-application-dns.net
            ''
          ];
        };
        allowlists.pl = [
          "whiomplatform.hwcloudtest.cn"
          "*.hwcloudtest.cn"
        ];
        clientGroupsBlock.default = [
          "pl"
          "doh-bypass"
        ];
        blockType = "zeroIp";
        blockTTL = "1h";
        loading = {
          refreshPeriod = "24h";
          downloads = {
            timeout = "90s";
            readTimeout = "90s";
            attempts = 5;
          };
        };
      };

      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };
    };
  };

}
