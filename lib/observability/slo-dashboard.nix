# SLI/SLO dashboard for the signals that matter to this small appliance.
{ pkgs, builder }:
let
  inherit (builder) mkStat mkText;
in
pkgs.writeText "slo-overview.json" (
  builtins.toJSON {
    title = "Reliability Overview";
    uid = "slo-overview";
    editable = false;
    refresh = "1m";
    time = {
      from = "now-30d";
      to = "now";
    };
    tags = [
      "sli"
      "reliability"
    ];
    panels = [
      (mkText {
        id = 1;
        x = 0;
        y = 0;
        w = 24;
        h = 4;
        title = "Service levels";
        content = ''
          ## Reliability indicators

          These panels use the Prometheus history retained on Soyo. They are
          indicators, not a substitute for the manual recovery drills in
          `docs/testing.md`.
        '';
      })
      (mkStat {
        id = 2;
        x = 0;
        y = 4;
        w = 6;
        h = 6;
        title = "DNS/DHCP availability (30d)";
        expr = ''100 * avg(avg_over_time(up{job=~"blocky|dnsmasq"}[30d]))'';
        unit = "percent";
        decimals = 3;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 99.0;
          }
          {
            color = "green";
            value = 99.9;
          }
        ];
      })
      (mkStat {
        id = 3;
        x = 6;
        y = 4;
        w = 6;
        h = 6;
        title = "Scrape availability (24h)";
        expr = "100 * avg(avg_over_time(up[24h]))";
        unit = "percent";
        decimals = 3;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 99.0;
          }
          {
            color = "green";
            value = 99.9;
          }
        ];
      })
      (mkStat {
        id = 4;
        x = 12;
        y = 4;
        w = 6;
        h = 6;
        title = "Last backup result (48h)";
        expr = "100 * last_over_time(restic_backup_success[48h])";
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 95;
          }
          {
            color = "green";
            value = 100;
          }
        ];
      })
      (mkStat {
        id = 5;
        x = 18;
        y = 4;
        w = 6;
        h = 6;
        title = "Prometheus targets up";
        expr = "100 * avg(up)";
        unit = "percent";
        decimals = 1;
        thresholds = [
          {
            color = "red";
            value = null;
          }
          {
            color = "yellow";
            value = 99;
          }
          {
            color = "green";
            value = 100;
          }
        ];
      })
    ];
  }
)
