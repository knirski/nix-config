# LAN Overview dashboard — blackbox probe insights and device inventory.
{ pkgs }:
pkgs.writeText "lan-overview.json" (
  builtins.toJSON {
    title = "LAN Overview";
    uid = "lan-overview";
    editable = false;
    refresh = "30s";
    time = {
      from = "now-6h";
      to = "now";
    };
    tags = [
      "lan"
      "network"
      "blackbox"
    ];
    panels = [
      {
        id = 1;
        type = "table";
        title = "Infrastructure Reachability";
        gridPos = {
          x = 0;
          y = 0;
          w = 12;
          h = 8;
        };
        targets = [
          {
            refId = "A";
            datasource = {
              type = "prometheus";
              uid = "soyo-prometheus";
            };
            expr = "max by (display_name, target_kind, instance, job) (probe_success{job=~\"blackbox-(icmp|http)\", site=\"lan\"})";
            format = "table";
            instant = true;
          }
        ];
      }
      {
        id = 2;
        type = "timeseries";
        title = "Probe Latency";
        gridPos = {
          x = 12;
          y = 0;
          w = 12;
          h = 8;
        };
        targets = [
          {
            refId = "A";
            datasource = {
              type = "prometheus";
              uid = "soyo-prometheus";
            };
            expr = "probe_duration_seconds{job=~\"blackbox-(icmp|http)\", site=\"lan\"}";
            legendFormat = "{{display_name}} ({{job}})";
          }
        ];
      }
      {
        id = 3;
        type = "table";
        title = "Known Devices";
        gridPos = {
          x = 0;
          y = 8;
          w = 16;
          h = 10;
        };
        targets = [
          {
            refId = "A";
            datasource = {
              type = "prometheus";
              uid = "soyo-prometheus";
            };
            expr = "lan_device_seen{name!~\"unknown-.*\"}";
            format = "table";
            instant = true;
          }
        ];
      }
      {
        id = 4;
        type = "table";
        title = "Unknown Devices";
        gridPos = {
          x = 16;
          y = 8;
          w = 8;
          h = 10;
        };
        targets = [
          {
            refId = "A";
            datasource = {
              type = "prometheus";
              uid = "soyo-prometheus";
            };
            expr = "lan_device_seen{name=~\"unknown-.*\"}";
            format = "table";
            instant = true;
          }
        ];
      }
      {
        id = 5;
        type = "table";
        title = "Reservations Currently Absent";
        gridPos = {
          x = 0;
          y = 18;
          w = 24;
          h = 8;
        };
        targets = [
          {
            refId = "A";
            datasource = {
              type = "prometheus";
              uid = "soyo-prometheus";
            };
            expr = "lan_device_reserved unless on (ip, name, mac) lan_device_seen";
            format = "table";
            instant = true;
          }
        ];
      }
    ];
  }
)
