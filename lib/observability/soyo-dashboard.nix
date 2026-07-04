# Soyo Control Plane dashboard — appliance drilldown for DNS, DHCP, capacity.
{
  lib,
  pkgs,
  builder,
}:
let
  inherit (builder) mkText mkStat mkTimeseries;

  fsUsed =
    mountpoint:
    ''100 * (1 - (node_filesystem_avail_bytes{mountpoint="${mountpoint}",fstype!=""} / node_filesystem_size_bytes{mountpoint="${mountpoint}",fstype!=""}))'';

  persistFree = ''100 * (node_filesystem_avail_bytes{mountpoint="/persist",fstype!=""} / node_filesystem_size_bytes{mountpoint="/persist",fstype!=""})'';

  blockRate30m = ''100 * sum(rate(blocky_query_total{reason="BLOCKED"}[30m])) / clamp_min(sum(rate(blocky_query_total[30m])), 0.001)'';

  cacheHitRate30m = "100 * sum(rate(dnsmasq_cache_hits[30m])) / clamp_min(sum(rate(dnsmasq_cache_hits[30m])) + sum(rate(dnsmasq_cache_misses[30m])), 0.001)";

  blockRate5m = ''100 * sum(rate(blocky_query_total{reason="BLOCKED"}[5m])) / clamp_min(sum(rate(blocky_query_total[5m])), 0.001)'';

  cacheHitRate5m = "100 * sum(rate(dnsmasq_cache_hits[5m])) / clamp_min(sum(rate(dnsmasq_cache_hits[5m])) + sum(rate(dnsmasq_cache_misses[5m])), 0.001)";

  refIds = [
    "A"
    "B"
    "C"
    "D"
  ];
in
pkgs.writeText "soyo-home.json" (
  builtins.toJSON {
    title = "Soyo Control Plane";
    uid = "soyo-home";
    tags = [
      "home"
      "soyo"
    ];
    editable = false;
    time = {
      from = "now-12h";
      to = "now";
    };
    refresh = "30s";
    templating.list = [ ];
    panels = [
      (mkText {
        id = 1;
        x = 0;
        y = 0;
        w = 24;
        h = 5;
        title = "Overview";
        content = ''
          ## Soyo at a glance

          This is the Soyo-specific drilldown from **Fleet Overview**. Stay here when you care about the appliance role itself: DNS, DHCP, filtering, cache behaviour, and `/persist` capacity.

          **Open next**
          - **Fleet Overview** for generic host health across the lab
          - **Blocky** for resolver and blocking behaviour
          - **dnsmasq** for leases, cache, and upstream forwarding
          - **Node Exporter Full** for low-level host internals

          **Healthy by default**
          - `Blocky` and `dnsmasq` stay **Up**
          - `/persist free` stays well above **10%**
          - query traffic and block rate move with normal LAN activity
        '';
      })
      (mkStat {
        id = 2;
        x = 0;
        y = 5;
        w = 4;
        h = 4;
        title = "Blocky";
        expr = ''max(up{job="blocky"})'';
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "green";
            value = 1;
          }
        ];
        mappings = [
          {
            type = "value";
            options = {
              "0" = {
                text = "Down";
                color = "red";
              };
              "1" = {
                text = "Up";
                color = "green";
              };
            };
          }
        ];
        description = "Resolver and filtering frontend";
      })
      (mkStat {
        id = 3;
        x = 4;
        y = 5;
        w = 4;
        h = 4;
        title = "dnsmasq";
        expr = ''max(up{job="dnsmasq"})'';
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "green";
            value = 1;
          }
        ];
        mappings = [
          {
            type = "value";
            options = {
              "0" = {
                text = "Down";
                color = "red";
              };
              "1" = {
                text = "Up";
                color = "green";
              };
            };
          }
        ];
        description = "DHCP and reverse DNS backend";
      })
      (mkStat {
        id = 4;
        x = 8;
        y = 5;
        w = 4;
        h = 4;
        title = "DHCP Leases";
        expr = "max(dnsmasq_leases)";
        thresholds = [
          {
            color = "blue";
            value = null;
          }
        ];
        description = "Current active leases";
      })
      (mkStat {
        id = 5;
        x = 12;
        y = 5;
        w = 4;
        h = 4;
        title = "Block Rate";
        expr = blockRate30m;
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "blue";
            value = null;
          }
          {
            color = "green";
            value = 5;
          }
        ];
        description = "Share of DNS queries blocked over the last 30 minutes";
      })
      (mkStat {
        id = 6;
        x = 16;
        y = 5;
        w = 4;
        h = 4;
        title = "Cache Hit Rate";
        expr = cacheHitRate30m;
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 40;
          }
          {
            color = "green";
            value = 70;
          }
        ];
        description = "dnsmasq cache efficiency over the last 30 minutes";
      })
      (mkStat {
        id = 7;
        x = 20;
        y = 5;
        w = 4;
        h = 4;
        title = "/persist Free";
        expr = persistFree;
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 15;
          }
          {
            color = "green";
            value = 25;
          }
        ];
        description = "Durable storage headroom";
      })
      (mkTimeseries {
        id = 8;
        x = 0;
        y = 9;
        w = 12;
        h = 10;
        title = "DNS Pipeline";
        unit = "short";
        refIds = refIds;
        description = "Incoming queries, blocked queries, and dnsmasq upstream forwards";
        targets = [
          {
            expr = "sum(rate(blocky_query_total[5m]))";
            legend = "Queries";
          }
          {
            expr = ''sum(rate(blocky_query_total{reason="BLOCKED"}[5m]))'';
            legend = "Blocked";
          }
          {
            expr = "sum(rate(dnsmasq_servers_queries[5m]))";
            legend = "Forwarded upstream";
          }
        ];
      })
      (mkTimeseries {
        id = 9;
        x = 12;
        y = 9;
        w = 12;
        h = 10;
        title = "Host Pressure";
        unit = "percent";
        refIds = refIds;
        description = "Capacity trends that can eventually threaten the appliance role";
        targets = [
          {
            expr = ''100 - avg by (mode) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100'';
            legend = "CPU busy";
          }
          {
            expr = "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))";
            legend = "Memory used";
          }
          {
            expr = fsUsed "/";
            legend = "/ used";
          }
          {
            expr = fsUsed "/persist";
            legend = "/persist used";
          }
        ];
      })
      (mkTimeseries {
        id = 10;
        x = 0;
        y = 19;
        w = 12;
        h = 8;
        title = "LAN Traffic";
        unit = "Bps";
        refIds = [
          "A"
          "B"
        ];
        targets = [
          {
            expr = ''rate(node_network_receive_bytes_total{device="enp1s0"}[5m])'';
            legend = "RX";
          }
          {
            expr = ''rate(node_network_transmit_bytes_total{device="enp1s0"}[5m])'';
            legend = "TX";
          }
        ];
      })
      (mkTimeseries {
        id = 11;
        x = 12;
        y = 19;
        w = 12;
        h = 8;
        title = "Filter Efficiency";
        unit = "percent";
        refIds = [
          "A"
          "B"
        ];
        description = "Short-window effectiveness signals for blocking and cache reuse";
        targets = [
          {
            expr = blockRate5m;
            legend = "Block rate";
          }
          {
            expr = cacheHitRate5m;
            legend = "Cache hit rate";
          }
        ];
      })
    ];
  }
)
