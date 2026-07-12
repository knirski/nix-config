{
  aspects.nixos.observability =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.observability;
      hardening = import ../../lib/systemd-hardening.nix;
      grafanaCfg = cfg.grafana;

      inherit (cfg) networkData;
      deviceMeta = networkData.deviceMeta or { };

      reservationProbeTargets = lib.concatMap (
        r:
        let
          meta = deviceMeta.${r.name} or null;
        in
        lib.optionals ((meta != null) && (meta.monitor or false)) [
          {
            inherit (r) name ip;
            kind = meta.kind or "host";
            displayName = meta.displayName or r.name;
          }
        ]
      ) networkData.reservations;

      probeTargets =
        reservationProbeTargets
        ++ (map (
          t:
          t
          // {
            displayName = t.displayName or t.name;
          }
        ) networkData.monitoredInfrastructure);

      httpProbeTargets = lib.filter (t: t ? probeHttpUrl) probeTargets;

      builder = import ../../lib/observability/dashboard-builder.nix {
        inherit lib pkgs;
        ds = "soyo-prometheus";
      };
      soyoBuilder = import ../../lib/observability/dashboard-builder.nix {
        inherit lib pkgs;
        ds = "soyo-prometheus";
        fillOpacity = 16;
      };

      fleetJson = import ../../lib/observability/fleet-dashboard.nix {
        inherit pkgs;
        inherit builder;
      };
      homeJson = import ../../lib/observability/soyo-dashboard.nix {
        inherit pkgs;
        builder = soyoBuilder;
      };
      lanOverviewJson = import ../../lib/observability/lan-dashboard.nix {
        inherit pkgs;
      };

      lanInventoryNetworkJson = pkgs.writeText "lan-network.json" (builtins.toJSON cfg.networkData);
      lanInventoryScript = pkgs.writeShellApplication {
        name = "lan-inventory-exporter";
        runtimeInputs = [
          pkgs.iproute2
          pkgs.python3
        ];
        text = ''
          set -euo pipefail
          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          ${pkgs.iproute2}/bin/ip -json neigh show dev enp1s0 > "$tmpdir/neighbors.json"

          exec ${pkgs.python3}/bin/python3 ${./observability/lan_inventory.py} \
            --network-data ${lanInventoryNetworkJson} \
            --leases ${cfg.dnsmasqExporter.leasesPath} \
            --neighbors "$tmpdir/neighbors.json" \
            --vendor-db ${pkgs.arp-scan}/etc/arp-scan/mac-vendor.txt \
            --output /var/lib/prometheus/textfiles/lan_inventory.prom
        '';
      };

      dnsmasqJson = builder.fillTemplating {
        replacements = [
          {
            key = "DS_PROMETHEUS";
            value = "soyo-prometheus";
          }
          {
            key = "datasource";
            value = "soyo-prometheus";
          }
          {
            key = "job";
            value = "dnsmasq";
          }
          {
            key = "instance";
            value = "localhost:9153";
          }
        ];
        tags = [
          "dnsmasq"
          "dhcp"
          "dns"
        ];
        dashboard = builder.fetchDashboard {
          id = 18796;
          hash = "1nn4nvbq7q2d4cbsmlr1796if3j6ndpyh0r19w6xy2iwxmxdx0a2";
        };
      };
      blockyJson = builder.fillTemplating {
        replacements = [
          {
            key = "DS_PROMETHEUS";
            value = "soyo-prometheus";
          }
          {
            key = "datasource";
            value = "soyo-prometheus";
          }
          {
            key = "job";
            value = "blocky";
          }
          {
            key = "instance";
            value = "localhost:4000";
          }
        ];
        tags = [
          "blocky"
          "dns"
          "adblock"
        ];
        dashboard = builder.fetchDashboard {
          id = 13768;
          hash = "0lci2a09ghmjab226m06shcmyxh11pqld0hkjv9ibv22fmrcw0w3";
        };
      };
      nodeExporterDashboard = builder.fillTemplating {
        replacements = [
          {
            key = "ds_prometheus";
            value = "soyo-prometheus";
          }
          {
            key = "job";
            value = "node";
          }
        ];
        tags = [
          "linux"
          "node-exporter"
        ];
        dashboard = builder.fetchDashboard {
          id = 1860;
          hash = "11hrll7fm626ikbva5md4gm0rca537vp4xsxa9sxl1pk15s6nk0q";
        };
      };
      # Keep JSON transformation at build time. Reading a generated store path
      # with builtins.readFile would require import-from-derivation and makes
      # clean `nix flake check --no-build` runners depend on a warm store.
      nodeExporterJson =
        pkgs.runCommand "node-exporter-full-root.json"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            ${pkgs.jq}/bin/jq '. + {uid: "node-exporter-root"}' ${nodeExporterDashboard} > "$out"
          '';

      inherit (builder) mkStaticLabelTarget;

      # Reusable fragments live under lib/observability/ (not modules/) because
      # import-tree auto-imports every .nix under modules/ as a flake-parts
      # module. lib/ is outside modules/ scope, so these are plain Nix functions
      # called here and spliced into config via mkMerge.
      #
      # networkData is supplied by the host (hosts/soyo/network.nix) and carries
      # three sub-structures:
      #   reservations     — from the DHCP schema (source of truth for who's on LAN)
      #   monitoredInfrastructure — off-DHCP or off-LAN targets to probe anyway
      #   deviceMeta       — observability-only labels (kind, displayName, monitor
      #                      flag) keyed by reservation name, keeping rich labels
      #                      off the reservations schema so the critical path stays boring.
      alloyConfig = import ../../lib/observability/alloy-config.nix { };
      grafanaAlertSetup = import ../../lib/observability/grafana-alert-setup.nix {
        inherit lib config pkgs;
      };
      tempoTraces = import ../../lib/observability/tempo-traces.nix {
        inherit lib pkgs;
      };
    in
    {
      options.lanAppliance.services.observability = {
        enable = lib.mkEnableOption "prometheus node_exporter, dnsmasq exporter, and optional on-box Grafana dashboards";

        nodeExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Listen address (IP only, no port — the module appends its default :9100).";
          };
        };

        dnsmasqExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Listen address (IP only, no port — the module appends its default :9153).";
          };
          dnsmasqListenAddress = lib.mkOption {
            type = lib.types.str;
            default = "soyo:5353";
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
            default = "soyo";
            description = "Grafana listen address (the module appends :3000).";
          };
          domain = lib.mkOption {
            type = lib.types.str;
            default = "soyo";
            description = "Grafana root URL domain (used for redirects and links).";
          };
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open the LAN firewall for exporter ports (9100, 9153) and Grafana (3000).";
        };

        networkData = lib.mkOption {
          type = lib.types.submodule {
            options = {
              reservations = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      name = lib.mkOption { type = lib.types.str; };
                      mac = lib.mkOption { type = lib.types.str; };
                      ip = lib.mkOption { type = lib.types.str; };
                    };
                  }
                );
                default = [ ];
                description = "DHCP/DNS reservation list, same shape as hosts/soyo/reservations.nix.";
              };
              monitoredInfrastructure = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      name = lib.mkOption { type = lib.types.str; };
                      ip = lib.mkOption { type = lib.types.str; };
                      kind = lib.mkOption { type = lib.types.str; };
                      displayName = lib.mkOption { type = lib.types.str; };
                      probeHttpUrl = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                      };
                    };
                  }
                );
                default = [ ];
                description = "Infrastructure targets that should always be probed (e.g. non-DHCP or off-LAN devices).";
              };
              deviceMeta = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options = {
                      kind = lib.mkOption { type = lib.types.str; };
                      displayName = lib.mkOption { type = lib.types.str; };
                      monitor = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                      };
                    };
                  }
                );
                default = { };
                description = "Observability-only labels keyed by reservation name — keeps rich labels off the DHCP schema.";
              };
            };
          };
          default = {
            reservations = [ ];
            monitoredInfrastructure = [ ];
            deviceMeta = { };
          };
          description = "Host-local network data used for LAN dashboards, blackbox probes, and passive inventory.";
        };

        blackboxExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Loopback listen address for blackbox_exporter (module appends :9115).";
          };
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.prometheus.exporters = {
              node = {
                enable = true;
                listenAddress = cfg.nodeExporter.listenAddress;
                extraFlags = [
                  "--collector.textfile.directory=/var/lib/prometheus/textfiles"
                  "--collector.processes"
                  "--collector.interrupts"
                ];
              };
              dnsmasq = {
                enable = true;
                listenAddress = cfg.dnsmasqExporter.listenAddress;
                dnsmasqListenAddress = cfg.dnsmasqExporter.dnsmasqListenAddress;
                leasesPath = cfg.dnsmasqExporter.leasesPath;
              };
              blackbox = {
                enable = true;
                listenAddress = cfg.blackboxExporter.listenAddress;
                configFile = pkgs.writeText "blackbox.yml" (
                  builtins.toJSON {
                    modules = {
                      icmp.prober = "icmp";
                      http_2xx = {
                        prober = "http";
                        timeout = "5s";
                        http = {
                          preferred_ip_protocol = "ip4";
                          method = "GET";
                        };
                      };
                    };
                  }
                );
              };
            };

            users.users.node-exporter.extraGroups = [ "prometheus" ];

            networking.firewall = lib.mkIf cfg.openFirewall {
              interfaces.enp1s0.allowedTCPPorts = lib.optionals grafanaCfg.enable [ 3000 ];
            };

            systemd = {
              services = {
                prometheus-node-exporter.serviceConfig = {
                  MemoryMax = "64M";
                  CPUQuota = "10%";
                  Nice = 10;
                };
                prometheus-dnsmasq-exporter.serviceConfig = {
                  MemoryMax = "64M";
                  CPUQuota = "10%";
                  Nice = 10;
                };
                prometheus-blackbox-exporter.serviceConfig = {
                  MemoryMax = "96M";
                  CPUQuota = "10%";
                  Nice = 10;
                };
                lan-inventory-exporter = {
                  description = "Emit passive LAN inventory metrics for node_exporter textfile collector";
                  after = [
                    "network-online.target"
                    "dnsmasq.service"
                  ];
                  wants = [ "network-online.target" ];
                  serviceConfig = hardening.offline // {
                    Type = "oneshot";
                    User = "prometheus";
                    Group = "prometheus";
                    SupplementaryGroups = [ "dnsmasq" ];
                    ExecStart = "${lanInventoryScript}/bin/lan-inventory-exporter";
                    MemoryMax = "96M";
                    CPUQuota = "10%";
                    Nice = 10;
                    ReadWritePaths = [ "/var/lib/prometheus/textfiles" ];
                    TimeoutStartSec = "1m";
                    Restart = "no";
                  };
                };
              };
              timers.lan-inventory-exporter = {
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnBootSec = "2m";
                  OnUnitActiveSec = "5m";
                  RandomizedDelaySec = "30s";
                  Unit = "lan-inventory-exporter.service";
                };
              };
              tmpfiles.rules = [
                "d /var/lib/prometheus/textfiles 0755 prometheus prometheus -"
              ];
            };
          }

          # --- On-box Grafana + Prometheus (optional guest service) ---
          (lib.mkIf grafanaCfg.enable (
            lib.mkMerge [
              {
                age.secrets = {
                  grafana-admin-password = {
                    rekeyFile = ../../secrets/grafana-admin-password.age;
                    owner = "grafana";
                  };
                  grafana-secret-key = {
                    rekeyFile = ../../secrets/grafana-secret-key.age;
                    owner = "grafana";
                  };
                };
                services = {
                  prometheus = {
                    enable = true;
                    listenAddress = "localhost";
                    port = 9090;
                    scrapeConfigs = [
                      {
                        job_name = "node";
                        static_configs = [ { targets = [ "localhost:9100" ]; } ];
                      }
                      {
                        job_name = "dnsmasq";
                        static_configs = [ { targets = [ "localhost:9153" ]; } ];
                      }
                      {
                        job_name = "blocky";
                        static_configs = [ { targets = [ "localhost:4000" ]; } ];
                      }
                    ];
                  };
                  loki = {
                    enable = true;
                    configuration = {
                      auth_enabled = false;
                      analytics.reporting_enabled = false;

                      server = {
                        http_listen_port = 3100;
                        http_listen_address = "localhost";
                        log_level = "warn";
                      };

                      ingester = {
                        lifecycler = {
                          address = "127.0.0.1";
                          ring = {
                            kvstore.store = "inmemory";
                            replication_factor = 1;
                          };
                          final_sleep = "0s";
                        };
                        chunk_idle_period = "5m";
                        chunk_retain_period = "30s";
                        wal = {
                          enabled = true;
                          dir = "/var/lib/loki/wal";
                        };
                      };

                      query_scheduler.use_scheduler_ring = false;

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
                          active_index_directory = "/var/lib/loki/tsdb-index";
                          cache_location = "/var/lib/loki/tsdb-cache";
                          cache_ttl = "24h";
                        };
                        filesystem.directory = "/var/lib/loki/chunks";
                      };

                      compactor = {
                        working_directory = "/var/lib/loki/compactor";
                        retention_enabled = true;
                        delete_request_store = "filesystem";
                      };

                      limits_config = {
                        reject_old_samples = true;
                        reject_old_samples_max_age = "168h";
                        retention_period = "720h";
                        allow_structured_metadata = false;
                        ingestion_rate_mb = 12;
                        ingestion_burst_size_mb = 18;
                      };
                    };
                  };
                  alloy = {
                    enable = true;
                    extraFlags = [ "--disable-reporting" ];
                  };
                  grafana =
                    let
                      config' = {
                        server = {
                          http_addr = "0.0.0.0";
                          http_port = 3000;
                          inherit (grafanaCfg) domain;
                          root_url = "http://${grafanaCfg.domain}:3000";
                        };
                        analytics.reporting_enabled = false;
                        grafana_news.new_news_enabled = false;
                        security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
                        security.admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
                        unified_alerting.enabled = true;
                        dashboards.default_home_dashboard_path = "${fleetJson}";
                      };
                    in
                    {
                      enable = true;
                      settings = config';
                      provision.datasources.settings = {
                        apiVersion = 1;
                        datasources = [
                          {
                            name = "Prometheus";
                            type = "prometheus";
                            access = "proxy";
                            url = "http://localhost:9090";
                            uid = "soyo-prometheus";
                            isDefault = true;
                          }
                          {
                            name = "Loki";
                            type = "loki";
                            access = "proxy";
                            url = "http://localhost:3100";
                            uid = "soyo-loki";
                          }
                          {
                            name = "Tempo";
                            type = "tempo";
                            access = "proxy";
                            url = "http://localhost:3200";
                            uid = "soyo-tempo";
                          }
                        ];
                      };
                      provision.dashboards.settings = {
                        apiVersion = 1;
                        providers = [
                          {
                            name = "fleet";
                            type = "file";
                            options.path = pkgs.runCommand "fleet-grafana-dashboards" { } ''
                              mkdir -p $out
                              cp ${fleetJson} $out/001-fleet-overview.json
                              cp ${nodeExporterJson} $out/002-node-exporter-full.json
                              cp ${lanOverviewJson} $out/003-lan-overview.json
                            '';
                          }
                          {
                            name = "soyo";
                            type = "file";
                            folder = "Soyo";
                            folderUid = "soyo";
                            options.path = pkgs.runCommand "soyo-grafana-dashboards" { } ''
                              mkdir -p $out
                              cp ${homeJson} $out/001-soyo-control-plane.json
                              cp ${dnsmasqJson} $out/dnsmasq.json
                              cp ${blockyJson} $out/blocky.json
                            '';
                          }
                        ];
                      };
                    };
                };
                environment.etc."alloy/config.alloy".text = alloyConfig;
              }
              {
                systemd.services = {
                  grafana.serviceConfig = {
                    MemoryMax = "256M";
                    CPUQuota = "20%";
                    Nice = 10;
                  };
                  prometheus.serviceConfig = {
                    MemoryMax = "512M";
                    CPUQuota = "30%";
                    Nice = 10;
                  };
                  loki.serviceConfig = {
                    MemoryMax = "512M";
                    CPUQuota = "20%";
                    Nice = 10;
                  };
                  alloy.serviceConfig = {
                    MemoryMax = "128M";
                    CPUQuota = "10%";
                    Nice = 10;
                  };
                };
              }
              grafanaAlertSetup
              tempoTraces
            ]
          ))

          # --- Blackbox probe jobs (grafana-dependent: needs Prometheus) ---
          (lib.mkIf grafanaCfg.enable {
            services.prometheus.scrapeConfigs = [
              {
                job_name = "blackbox-exporter";
                static_configs = [ { targets = [ "127.0.0.1:9115" ]; } ];
              }
              {
                job_name = "blackbox-icmp";
                metrics_path = "/probe";
                params.module = [ "icmp" ];
                static_configs = map (t: mkStaticLabelTarget t t.ip) probeTargets;
                relabel_configs = [
                  {
                    source_labels = [ "__address__" ];
                    target_label = "__param_target";
                  }
                  {
                    source_labels = [ "__param_target" ];
                    target_label = "instance";
                  }
                  {
                    target_label = "__address__";
                    replacement = "127.0.0.1:9115";
                  }
                ];
              }
              {
                job_name = "blackbox-http";
                metrics_path = "/probe";
                params.module = [ "http_2xx" ];
                static_configs = map (t: mkStaticLabelTarget t t.probeHttpUrl) httpProbeTargets;
                relabel_configs = [
                  {
                    source_labels = [ "__address__" ];
                    target_label = "__param_target";
                  }
                  {
                    source_labels = [ "__param_target" ];
                    target_label = "instance";
                  }
                  {
                    target_label = "__address__";
                    replacement = "127.0.0.1:9115";
                  }
                ];
              }
            ];
          })
        ]
      );
    };
}
