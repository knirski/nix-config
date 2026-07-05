# Fleet Overview dashboard — default landing page for multi-host labs.
{ pkgs, builder }:
let
  inherit (builder)
    mkText
    mkStat
    mkTimeseries
    ;

  refIds = [
    "A"
    "B"
  ];
in
pkgs.writeText "fleet-overview.json" (
  builtins.toJSON {
    title = "Fleet Overview";
    uid = "fleet-overview";
    tags = [
      "home"
      "fleet"
    ];
    editable = false;
    time = {
      from = "now-1h";
      to = "now";
    };
    refresh = "30s";
    templating.list = [
      {
        allowCustomValue = false;
        current = {
          text = "All";
          value = "$__all";
        };
        definition = ''label_values(up{job="node"}, instance)'';
        includeAll = true;
        name = "hosts";
        options = [ ];
        query = {
          qryType = 1;
          query = ''label_values(up{job="node"}, instance)'';
          refId = "PrometheusVariableQueryEditor-VariableQuery";
        };
        refresh = 1;
        regex = "";
        type = "query";
      }
    ];
    panels = [
      (mkText {
        id = 1;
        x = 0;
        y = 0;
        w = 24;
        h = 5;
        title = "Overview";
        content = ''
          ## Fleet at a glance

          This is the default Grafana landing page for a multi-host lab. Keep it generic: uptime, capacity, and network posture per host here; service- and role-specific details stay in their own dashboards.

          **Open next**
          - **Soyo Control Plane** for DNS, DHCP, Blocky, dnsmasq, and `/persist`
          - **Node Exporter Full** for low-level host internals
          - **Blocky** and **dnsmasq** for service drilldowns

          **Healthy by default**
          - every `node` scrape target stays **Up**
          - scrape target availability stays near **100%**
          - `Soyo DNS/DHCP` stays at **2 / 2**
        '';
      })
      (mkStat {
        id = 2;
        x = 0;
        y = 5;
        w = 6;
        h = 4;
        title = "Nodes Up";
        expr = ''sum(up{job="node"})'';
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
        description = "node_exporter targets currently reachable";
      })
      (mkStat {
        id = 3;
        x = 6;
        y = 5;
        w = 6;
        h = 4;
        title = "Hosts Defined";
        expr = ''count(up{job="node"})'';
        thresholds = [
          {
            color = "blue";
            value = null;
          }
        ];
        description = "Hosts currently represented in Prometheus";
      })
      (mkStat {
        id = 4;
        x = 12;
        y = 5;
        w = 6;
        h = 4;
        title = "Targets Up";
        expr = "100 * sum(up) / clamp_min(count(up), 1)";
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 90;
          }
          {
            color = "green";
            value = 100;
          }
        ];
        description = "Availability across all Prometheus scrape targets";
      })
      (mkStat {
        id = 5;
        x = 18;
        y = 5;
        w = 6;
        h = 4;
        title = "Soyo DNS/DHCP";
        expr = ''sum(up{job=~"blocky|dnsmasq"})'';
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 1;
          }
          {
            color = "green";
            value = 2;
          }
        ];
        description = "Critical appliance services that must stay healthy";
      })
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 9;
        };
        id = 10;
        panels = [ ];
        repeat = "hosts";
        title = "$hosts";
        type = "row";
      }
      (mkStat {
        id = 11;
        x = 0;
        y = 10;
        w = 4;
        h = 7;
        title = "Uptime";
        expr = ''sum((node_time_seconds{instance=~"$hosts",job="node"} - node_boot_time_seconds{instance=~"$hosts",job="node"}) OR vector(0))'';
        unit = "s";
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
      })
      (mkStat {
        id = 12;
        x = 4;
        y = 10;
        w = 4;
        h = 7;
        title = "CPU Busy";
        expr = ''100 - avg(rate(node_cpu_seconds_total{mode="idle",instance=~"$hosts",job="node"}[5m])) * 100'';
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "green";
            value = null;
          }
          {
            color = "yellow";
            value = 50;
          }
          {
            color = "red";
            value = 75;
          }
        ];
      })
      (mkStat {
        id = 13;
        x = 8;
        y = 10;
        w = 4;
        h = 7;
        title = "RAM Used";
        expr = ''100 * (1 - (node_memory_MemAvailable_bytes{instance=~"$hosts",job="node"} / node_memory_MemTotal_bytes{instance=~"$hosts",job="node"}))'';
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "green";
            value = null;
          }
          {
            color = "yellow";
            value = 70;
          }
          {
            color = "red";
            value = 85;
          }
        ];
      })
      (mkStat {
        id = 14;
        x = 12;
        y = 10;
        w = 4;
        h = 7;
        title = "/ Used";
        expr = ''100 * (1 - (node_filesystem_avail_bytes{instance=~"$hosts",job="node",mountpoint="/",fstype!=""} / node_filesystem_size_bytes{instance=~"$hosts",job="node",mountpoint="/",fstype!=""}))'';
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "green";
            value = null;
          }
          {
            color = "yellow";
            value = 70;
          }
          {
            color = "red";
            value = 85;
          }
        ];
      })
      (mkTimeseries {
        id = 15;
        x = 16;
        y = 10;
        w = 8;
        h = 7;
        title = "Network";
        unit = "Bps";
        refIds = refIds;
        description = "Per-host traffic across non-loopback interfaces";
        targets = [
          {
            expr = ''sum(rate(node_network_receive_bytes_total{instance=~"$hosts",job="node",device!="lo"}[5m]))'';
            legend = "RX";
          }
          {
            expr = ''sum(rate(node_network_transmit_bytes_total{instance=~"$hosts",job="node",device!="lo"}[5m]))'';
            legend = "TX";
          }
        ];
      })
    ];
  }
)
