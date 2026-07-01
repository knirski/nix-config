{
  flake.modules.nixos.observability =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.observability;
      grafanaCfg = cfg.grafana;
    in
    {
      options.lanAppliance.services.observability = {
        enable = lib.mkEnableOption "prometheus node_exporter, dnsmasq exporter, and optional on-box Grafana dashboards";

        nodeExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9";
            description = "Listen address (IP only, no port — the module appends its default :9100).";
          };
        };

        dnsmasqExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9";
            description = "Listen address (IP only, no port — the module appends its default :9153).";
          };
          dnsmasqListenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9:53";
            description = "dnsmasq address for lease stats; must match where dnsmasq is reachable from Soyo.";
          };
          leasesPath = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/dnsmasq/dnsmasq.leases";
          };
        };

        grafana = {
          enable = lib.mkEnableOption "on-box Grafana dashboards (adds a local Prometheus scraper; resource-isolated as a guest service)";
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9";
            description = "Grafana listen address (the module appends :3000).";
          };
          domain = lib.mkOption {
            type = lib.types.str;
            default = "soyo.home.arpa";
            description = "Grafana root URL domain (used for redirects and links).";
          };
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open the LAN firewall for exporter ports (9100, 9153) and Grafana (3000).";
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.prometheus.exporters.node = {
              enable = true;
              listenAddress = cfg.nodeExporter.listenAddress;
            };

            services.prometheus.exporters.dnsmasq = {
              enable = true;
              listenAddress = cfg.dnsmasqExporter.listenAddress;
              dnsmasqListenAddress = cfg.dnsmasqExporter.dnsmasqListenAddress;
              leasesPath = cfg.dnsmasqExporter.leasesPath;
            };

            # Resource isolation: exporters are guest services; prevent them from
            # starving Blocky or dnsmasq under memory/CPU pressure.
            systemd.services.prometheus-node-exporter.serviceConfig = {
              MemoryMax = "64M";
              CPUQuota = "10%";
            };

            systemd.services.prometheus-dnsmasq-exporter.serviceConfig = {
              MemoryMax = "64M";
              CPUQuota = "10%";
            };

            networking.firewall = lib.mkIf cfg.openFirewall {
              interfaces.enp1s0.allowedTCPPorts = [
                9100
                9153
              ]
              ++ lib.optionals grafanaCfg.enable [ 3000 ];
            };
          }

          # --- On-box Grafana + Prometheus (optional guest service) ---
          (lib.mkIf grafanaCfg.enable {
            # Local Prometheus scraper: Grafana cannot consume /metrics endpoints
            # directly — it needs the Prometheus query API. Prometheus scrapes the
            # local exporters and serves that API on loopback :9090.
            services.prometheus = {
              enable = true;
              listenAddress = "127.0.0.1";
              port = 9090;
              scrapeConfigs = [
                {
                  job_name = "node";
                  static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
                }
                {
                  job_name = "dnsmasq";
                  static_configs = [ { targets = [ "127.0.0.1:9153" ]; } ];
                }
                {
                  job_name = "blocky";
                  static_configs = [ { targets = [ "127.0.0.1:4000" ]; } ];
                }
              ];
            };

            # Loki: lightweight log storage. Local filesystem backend, no S3
            # needed at this scale. Loopback-only, sits next to Grafana.
            services.loki = {
              enable = true;
              configuration = {
                auth_enabled = false;
                server = {
                  http_listen_port = 3100;
                  http_listen_address = "127.0.0.1";
                };
                ingester = {
                  chunk_idle_period = "5m";
                  chunk_retain_period = "30s";
                  wal = {
                    enabled = true;
                    dir = "/var/lib/loki/wal";
                  };
                };
                schema_config.configs = [
                  {
                    from = "2025-01-01";
                    store = "tsdb";
                    object_store = "filesystem";
                    schema = "v13";
                    index = {
                      prefix = "index_";
                      period = "24h";
                    };
                  }
                ];
                storage_config = {
                  tsdb_shipper = {
                    active_index_directory = "/var/lib/loki/index";
                    cache_location = "/var/lib/loki/cache";
                    shared_store = "filesystem";
                  };
                  filesystem.directory = "/var/lib/loki/chunks";
                };
                compactor = {
                  working_directory = "/var/lib/loki/compactor";
                  retention_enabled = true;
                };
                limits_config = {
                  reject_old_samples = true;
                  reject_old_samples_max_age = "168h";
                  retention_period = "720h"; # 30 days
                };
              };
            };

            # Grafana Alloy: ships systemd journal logs to Loki. Replaces the
            # EOL promtail. Reads the journal via the systemd-journal group.
            services.alloy = {
              enable = true;
              extraFlags = [ "--disable-reporting" ];
            };
            environment.etc."alloy/config.alloy".text = ''
              // Ship systemd journal to local Loki
              loki.source.journal "soyo" {
                max_age  = "12h"
                forward_to = [loki.write.local_loki]
                labels = {
                  job  = "systemd-journal",
                  host = "soyo",
                }
                relabel_rules {
                  rule { source_labels = ["__journal__systemd_unit"]; target_label = "unit" }
                  rule { source_labels = ["__journal__hostname"];    target_label = "hostname" }
                  rule { source_labels = ["__journal__priority"];    target_label = "priority" }
                  rule { source_labels = ["__journal__transport"];   target_label = "transport" }
                }
              }

              // Push to local Loki on loopback
              loki.write "local_loki" {
                endpoint {
                  url = "http://127.0.0.1:3100/loki/api/v1/push"
                }
              }
            '';

            services.grafana = {
              enable = true;
              settings = {
                server = {
                  http_addr = grafanaCfg.listenAddress;
                  http_port = 3000;
                  domain = grafanaCfg.domain;
                  root_url = "http://${grafanaCfg.domain}:3000";
                };
                analytics.reporting_enabled = false;
                grafana_news.new_news_enabled = false;
                # Required by Grafana 13+; LAN-only appliance, default key is fine.
                security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
              };
              provision.datasources.settings = {
                apiVersion = 1;
                datasources = [
                  {
                    name = "Prometheus";
                    type = "prometheus";
                    access = "proxy";
                    url = "http://127.0.0.1:9090";
                    isDefault = true;
                  }
                  {
                    name = "Loki";
                    type = "loki";
                    access = "proxy";
                    url = "http://127.0.0.1:3100";
                    uid = "soyo-loki";
                  }
                ];
              };
              provision.dashboards.settings = {
                apiVersion = 1;
                providers = [
                  {
                    name = "soyo";
                    type = "file";
                    options.path = pkgs.runCommand "soyo-grafana-dashboards" { } ''
                      mkdir -p $out
                      cp ${../../hosts/soyo/grafana/soyo-dashboard.json} $out/
                    '';
                  }
                ];
              };
            };

            # Resource isolation: Grafana, Loki, Prometheus, and Alloy are guest
            # services — prevent them from starving Blocky or dnsmasq.
            systemd.services.grafana.serviceConfig = {
              MemoryMax = "256M";
              CPUQuota = "20%";
              Nice = 10;
            };

            systemd.services.prometheus.serviceConfig = {
              MemoryMax = "512M";
              CPUQuota = "30%";
              Nice = 10;
            };

            systemd.services.loki.serviceConfig = {
              MemoryMax = "512M";
              CPUQuota = "20%";
              Nice = 10;
            };

            systemd.services.alloy.serviceConfig = {
              MemoryMax = "128M";
              CPUQuota = "10%";
              Nice = 10;
            };
          })
        ]
      );
    };
}
