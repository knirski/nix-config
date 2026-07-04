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
      grafanaCfg = cfg.grafana;

      networkData = cfg.networkData;
      deviceMeta = networkData.deviceMeta or { };

      reservationProbeTargets = lib.concatMap (
        r:
        let
          meta = deviceMeta.${r.name} or null;
        in
        lib.optionals ((meta != null) && ((meta.monitor or false))) [
          {
            name = r.name;
            ip = r.ip;
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
        inherit lib pkgs;
        builder = builder;
      };
      homeJson = import ../../lib/observability/soyo-dashboard.nix {
        inherit lib pkgs;
        builder = soyoBuilder;
      };
      lanOverviewJson = import ../../lib/observability/lan-dashboard.nix {
        inherit pkgs;
        inherit networkData;
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
      nodeExporterJson =
        let
          dashboard = builtins.fromJSON (
            builtins.readFile (
              builder.fillTemplating {
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
              }
            )
          );
        in
        pkgs.writeText "node-exporter-full-root.json" (
          builtins.toJSON (
            dashboard
            // {
              uid = "node-exporter-root";
            }
          )
        );

      mkStaticLabelTarget = builder.mkStaticLabelTarget;
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
            services.prometheus.exporters.node = {
              enable = true;
              listenAddress = cfg.nodeExporter.listenAddress;
              extraFlags = [
                "--collector.textfile.directory=/var/lib/prometheus/textfiles"
                "--collector.processes"
                "--collector.interrupts"
              ];
            };

            services.prometheus.exporters.dnsmasq = {
              enable = true;
              listenAddress = cfg.dnsmasqExporter.listenAddress;
              dnsmasqListenAddress = cfg.dnsmasqExporter.dnsmasqListenAddress;
              leasesPath = cfg.dnsmasqExporter.leasesPath;
            };

            users.users.node-exporter.extraGroups = [ "prometheus" ];

            systemd.services.prometheus-node-exporter.serviceConfig = {
              MemoryMax = "64M";
              CPUQuota = "10%";
            };

            systemd.services.prometheus-dnsmasq-exporter.serviceConfig = {
              MemoryMax = "64M";
              CPUQuota = "10%";
            };

            networking.firewall = lib.mkIf cfg.openFirewall {
              interfaces.enp1s0.allowedTCPPorts = lib.optionals grafanaCfg.enable [ 3000 ];
            };

            services.prometheus.exporters.blackbox = {
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

            systemd.services.prometheus-blackbox-exporter.serviceConfig = {
              MemoryMax = "96M";
              CPUQuota = "10%";
            };

            systemd.tmpfiles.rules = [
              "d /var/lib/prometheus/textfiles 0755 prometheus prometheus -"
            ];

            systemd.services.lan-inventory-exporter = {
              description = "Emit passive LAN inventory metrics for node_exporter textfile collector";
              after = [
                "network-online.target"
                "dnsmasq.service"
              ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                Type = "oneshot";
                User = "prometheus";
                Group = "prometheus";
                SupplementaryGroups = [ "dnsmasq" ];
                ExecStart = "${lanInventoryScript}/bin/lan-inventory-exporter";
                MemoryMax = "96M";
                CPUQuota = "10%";
              };
            };

            systemd.timers.lan-inventory-exporter = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "2m";
                OnUnitActiveSec = "5m";
                RandomizedDelaySec = "30s";
                Unit = "lan-inventory-exporter.service";
              };
            };
          }

          # --- On-box Grafana + Prometheus (optional guest service) ---
          (lib.mkIf grafanaCfg.enable {
            services.prometheus = {
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

            services.loki = {
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

            services.alloy = {
              enable = true;
              extraFlags = [ "--disable-reporting" ];
            };
            environment.etc."alloy/config.alloy".text = ''
              loki.relabel "journal_drilldown" {
                forward_to = []

                rule {
                  source_labels = ["__journal_syslog_identifier"]
                  regex         = "(.+)"
                  target_label  = "service_name"
                }

                rule {
                  source_labels = ["__journal__systemd_unit"]
                  regex         = "(.+)"
                  target_label  = "service_name"
                }

                rule {
                  source_labels = ["__journal_message"]
                  regex         = ".*"
                  replacement   = "unknown"
                  target_label  = "level"
                }

                rule {
                  source_labels = ["__journal_message"]
                  regex         = ".*"
                  replacement   = "unknown"
                  target_label  = "detected_level"
                }

                rule {
                  source_labels = ["__journal_priority_keyword"]
                  regex         = "(.+)"
                  target_label  = "level"
                }

                rule {
                  source_labels = ["__journal_priority_keyword"]
                  regex         = "(.+)"
                  target_label  = "detected_level"
                }

                rule {
                  source_labels = ["__journal__systemd_unit"]
                  regex         = "(.+)"
                  target_label  = "unit"
                }
              }

              loki.source.journal "soyo" {
                max_age       = "30m"
                forward_to    = [loki.write.local_loki.receiver]
                relabel_rules = loki.relabel.journal_drilldown.rules
                labels        = {
                  job  = "systemd-journal",
                  host = "soyo",
                }
              }

              loki.write "local_loki" {
                endpoint {
                  url = "http://localhost:3100/loki/api/v1/push"
                }
              }
            '';

            services.grafana =
              let
                config' = {
                  server = {
                    http_addr = "0.0.0.0";
                    http_port = 3000;
                    domain = grafanaCfg.domain;
                    root_url = "http://${grafanaCfg.domain}:3000";
                  };
                  analytics.reporting_enabled = false;
                  grafana_news.new_news_enabled = false;
                  security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
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

            # Grafana alert setup: provisions contact points, notification
            # policies, and alert rules via the Grafana HTTP API at boot.
            systemd.services.grafana-alert-setup = {
              description = "Provision Grafana alerting rules and ntfy contact point";
              after = [ "grafana.service" ];
              wants = [ "grafana.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 10;
                ExecStart =
                  let
                    script = pkgs.writeShellApplication {
                      name = "grafana-alert-setup";
                      runtimeInputs = [
                        pkgs.curl
                        pkgs.jq
                      ];
                      excludeShellChecks = [ "SC2086" ];
                      text = ''
                        set -eu
                        : "''${CREDENTIALS_DIRECTORY:=/dev/null}"
                        PASS=$(<"$CREDENTIALS_DIRECTORY"/admin_password)
                        AUTH="admin:$PASS"
                        BASE=http://127.0.0.1:3000
                        curl() { command curl -sf -u "$AUTH" "$@"; }

                        wait_ready() {
                          for _ in $(seq 1 30); do
                            curl "$BASE/api/health" >/dev/null 2>&1 && return 0
                            sleep 2
                          done
                          exit 1
                        }

                        ensure_folder() {
                          curl -s -o /dev/null -w '%{http_code}' \
                            -X POST -H 'Content-Type: application/json' \
                            -d '{"uid":"soyo","title":"Soyo"}' \
                            "$BASE/api/folders" | grep -qE '^200|^409'
                          curl -sS -o /dev/null -X PUT \
                            -H 'Content-Type: application/json' \
                            -d '{"uid":"soyo","title":"Soyo","overwrite":true}' \
                            "$BASE/api/folders/soyo" || :
                        }

                        cleanup_legacy_folder() {
                          local legacy_uids uid status
                          legacy_uids=$(command curl -sS -u "$AUTH" "$BASE/api/folders" \
                            | ${pkgs.jq}/bin/jq -r '.[] | select(.title == "soyo" and .uid != "soyo") | .uid')

                          for uid in $legacy_uids; do
                            status=$(command curl -sS -u "$AUTH" -o /dev/null -w '%{http_code}' \
                              -X DELETE "$BASE/api/folders/$uid")
                            [ "$status" = 200 ] || [ "$status" = 204 ] || [ "$status" = 404 ]
                          done
                        }

                        provision_contact_point() {
                          local topic token
                          topic=$(<"$CREDENTIALS_DIRECTORY"/ntfy_topic)
                          token=$(<"$CREDENTIALS_DIRECTORY"/ntfy_token)
                          ${pkgs.jq}/bin/jq -nc \
                            --arg url "$topic" \
                            --arg token "$token" \
                            '{name: "ntfy", type: "webhook", settings: {
                              url: ($url + "?template=yes&title=%7B%7B.title%7D%7D&message=%7B%7B.message%7D%7D&priority=5&tags=warning,soyo"),
                              httpMethod: "POST",
                              authorization: {type: "Bearer", credentials: $token}}}' \
                            | curl -X POST -H 'Content-Type: application/json' \
                              -d @- "$BASE/api/v1/provisioning/contact-points"
                        }

                        provision_policy() {
                          ${pkgs.jq}/bin/jq -nc \
                            '{receiver: "ntfy", group_by: ["severity", "team"],
                              group_wait: "30s", group_interval: "5m",
                              repeat_interval: "4h", routes: []}' \
                            | curl -X PUT -H 'Content-Type: application/json' \
                              -d @- "$BASE/api/v1/provisioning/policies"
                        }

                        delete_rule() {
                          local uid="$1" status
                          status=$(command curl -sS -u "$AUTH" -o /dev/null -w '%{http_code}' \
                            -X DELETE "$BASE/api/v1/provisioning/alert-rules/$uid")
                          [ "$status" = 200 ] || [ "$status" = 202 ] || [ "$status" = 404 ]
                        }

                        post_rule() {
                          local uid="$1"
                          delete_rule "$uid"
                          ${pkgs.jq}/bin/jq -nc \
                            --arg uid "$uid" --arg title "$2" \
                            --arg expr "$3" --arg for "$4" \
                            --arg noData "$5" --arg summary "$6" \
                            '{uid: $uid, title: $title,
                              folderUID: "soyo", ruleGroup: "soyo", orgID: 1,
                              condition: "A", noDataState: $noData,
                              execErrState: "Error", for: $for,
                              data: [{
                                refId: "A",
                                relativeTimeRange: {from: 600, to: 0},
                                datasourceUid: "soyo-prometheus",
                                model: {type: "prometheus", expr: $expr}
                              }],
                              annotations: {summary: $summary},
                              labels: {severity: "critical", team: "soyo"},
                              isPaused: false}' \
                            | curl -X POST -H 'Content-Type: application/json' \
                              -d @- "$BASE/api/v1/provisioning/alert-rules"
                        }

                        provision_rules() {
                          post_rule soyo_blocky_down \
                            "Service down: Blocky DNS" \
                            'up{job="blocky"} == 0' \
                            5m Alerting "Blocky DNS is unreachable"

                          post_rule soyo_dnsmasq_down \
                            "Service down: dnsmasq" \
                            'up{job="dnsmasq"} == 0' \
                            5m Alerting "dnsmasq unreachable — DHCP and reverse DNS down"

                          post_rule soyo_backup_failed \
                            "Backup failed" \
                            "restic_backup_success == 0" \
                            30m Alerting "restic backup to Synology failed — check journalctl"

                          post_rule soyo_disk_space_low \
                            "Disk space low on /persist" \
                            'node_filesystem_avail_bytes{mountpoint="/persist",fstype!=""} / node_filesystem_size_bytes{mountpoint="/persist",fstype!=""} * 100 < 10' \
                            5m NoData "/persist disk usage below 10%"
                        }

                        wait_ready
                        ensure_folder || :
                        cleanup_legacy_folder || :
                        provision_contact_point || :
                        provision_policy || :
                        provision_rules || :
                      '';
                    };
                  in
                  "${script}/bin/grafana-alert-setup";
                LoadCredential = [
                  "ntfy_topic:${config.age.secrets.ntfy-topic.path}"
                  "ntfy_token:${config.age.secrets.ntfy-token.path}"
                  "admin_password:${config.age.secrets.grafana-admin-password.path}"
                ];
              };
            };

            # Resource isolation
            systemd.services.grafana.serviceConfig = {
              MemoryMax = "256M";
              CPUQuota = "20%";
              Nice = 10;
            };

            systemd.tmpfiles.rules = [
              "d /persist/var/lib/tempo/generator-wal 0750 tempo tempo -"
              "d /persist/var/lib/tempo/generator-traces 0750 tempo tempo -"
            ];

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

            systemd.services.tempo.serviceConfig = {
              MemoryMax = "512M";
              CPUQuota = "20%";
              Nice = 10;
            };

            # Tempo
            services.tempo = {
              enable = true;
              settings = {
                target = "all";

                server = {
                  http_listen_port = 3200;
                  http_listen_address = "localhost";
                  grpc_listen_port = 4319;
                  grpc_listen_address = "localhost";
                };

                distributor.receivers = {
                  otlp.protocols = {
                    grpc = { };
                    http = { };
                  };
                };

                ingester = {
                  lifecycler.ring = {
                    kvstore.store = "inmemory";
                    replication_factor = 1;
                  };
                };

                storage.trace = {
                  backend = "local";
                  local.path = "/var/lib/tempo/traces";
                  wal.path = "/var/lib/tempo/wal";
                };

                metrics_generator = {
                  storage.path = "/var/lib/tempo/generator-wal";
                  traces_storage.path = "/var/lib/tempo/generator-traces";
                  processor.local_blocks = {
                    filter_server_spans = false;
                  };
                  processor.span_metrics.enable_target_info = true;
                  processor.service_graphs = {
                    dimensions = [ "service.name" ];
                    histogram_buckets = [
                      0.1
                      0.4
                      1.6
                      6.4
                      25.6
                      102.4
                      409.6
                    ];
                  };
                  ring.kvstore.store = "inmemory";
                };

                overrides = {
                  max_bytes_per_trace = 5000000;
                  metrics_generator_processors = [
                    "local-blocks"
                    "span-metrics"
                    "service-graphs"
                  ];
                };
              };
            };

            users.users.tempo = {
              description = "Tempo trace storage user";
              group = "tempo";
              isSystemUser = true;
            };
            users.groups.tempo = { };
            systemd.services.tempo.serviceConfig.DynamicUser = lib.mkForce false;

            # Boot trace
            systemd.services.soyo-boot-trace = {
              description = "Generate boot trace from systemd-analyze";
              after = [
                "multi-user.target"
                "tempo.service"
              ];
              wants = [ "tempo.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  let
                    tracer = pkgs.writeShellApplication {
                      name = "soyo-boot-trace";
                      runtimeInputs = [
                        pkgs.curl
                        pkgs.gawk
                        pkgs.jq
                        pkgs.util-linux
                      ];
                      text = ''
                        set -eu
                        TRACE_ID=$(uuidgen | tr 'A-F' 'a-f' | tr -d -)
                        SPAN_ID=$(uuidgen | tr 'A-F' 'a-f' | tr -d - | cut -c1-16)
                        START_NS=$(date +%s%N)
                        END_NS=$((START_NS + 1000000000))
                        TOP_UNITS=$(systemd-analyze blame 2>/dev/null | awk 'NR <= 10 { print $2 }' | paste -sd ',' -)
                        ${pkgs.jq}/bin/jq -nc \
                          --arg trace_id "$TRACE_ID" \
                          --arg span_id "$SPAN_ID" \
                          --arg start_ns "$START_NS" \
                          --arg end_ns "$END_NS" \
                          --arg top_units "$TOP_UNITS" \
                          '{
                            resourceSpans: [{
                              resource: {attributes: [
                                {key: "service.name", value: {stringValue: "systemd-boot"}},
                                {key: "host.name", value: {stringValue: "soyo"}}
                              ]},
                              scopeSpans: [{
                                scope: {name: "systemd-analyze"},
                                spans: [{
                                  traceId: $trace_id, spanId: $span_id,
                                  name: "systemd-boot", kind: 2,
                                  startTimeUnixNano: $start_ns, endTimeUnixNano: $end_ns,
                                  attributes: [
                                    {key: "boot.top_units", value: {stringValue: $top_units}}
                                  ]
                                }]
                              }]
                            }]
                          }' \
                          | ${pkgs.curl}/bin/curl -fsS -o /dev/null -X POST \
                            -H 'Content-Type: application/json' \
                            -d @- http://localhost:4318/v1/traces
                      '';
                    };
                  in
                  "${tracer}/bin/soyo-boot-trace";
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 19;
              };
            };

            # Activation trace
            systemd.services.soyo-activation-trace = {
              description = "Trace nixos-rebuild activation";
              after = [
                "multi-user.target"
                "tempo.service"
              ];
              wants = [ "tempo.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  let
                    tracer = pkgs.writeShellApplication {
                      name = "soyo-activation-trace";
                      runtimeInputs = [
                        pkgs.curl
                        pkgs.jq
                        pkgs.util-linux
                      ];
                      text = ''
                        set -eu
                        GEN_PATH=/run/current-system
                        [ -d "$GEN_PATH" ] || exit 0
                        TRACE_ID=$(uuidgen | tr 'A-F' 'a-f' | tr -d -)
                        SPAN_ID=$(uuidgen | tr 'A-F' 'a-f' | tr -d - | cut -c1-16)
                        START_NS=$(stat --format=%Y "$GEN_PATH")000000000
                        NOW_NS=$(date +%s%N)
                        GEN=$(nixos-version 2>/dev/null | cut -c1-40 || echo unknown)
                        ${pkgs.jq}/bin/jq -nc \
                          --arg trace_id "$TRACE_ID" \
                          --arg span_id "$SPAN_ID" \
                          --arg start_ns "$START_NS" \
                          --arg now_ns "$NOW_NS" \
                          --arg gen "$GEN" \
                          '{
                            resourceSpans: [{
                              resource: {attributes: [
                                {key: "service.name", value: {stringValue: "nixos-activation"}},
                                {key: "host.name", value: {stringValue: "soyo"}}
                              ]},
                              scopeSpans: [{
                                scope: {name: "nixos"},
                                spans: [{
                                  traceId: $trace_id, spanId: $span_id,
                                  name: ("nixos-activation-" + $gen), kind: 2,
                                  startTimeUnixNano: $start_ns, endTimeUnixNano: $now_ns,
                                  attributes: [
                                    {key: "generation", value: {stringValue: $gen}}
                                  ]
                                }]
                              }]
                            }]
                          }' \
                          | ${pkgs.curl}/bin/curl -fsS -o /dev/null -X POST \
                            -H 'Content-Type: application/json' \
                            -d @- http://localhost:4318/v1/traces
                      '';
                    };
                  in
                  "${tracer}/bin/soyo-activation-trace";
                MemoryMax = "32M";
                CPUQuota = "5%";
                Nice = 19;
              };
            };
            systemd.paths.soyo-activation-trace = {
              description = "Watch for NixOS activation";
              wantedBy = [ "multi-user.target" ];
              pathConfig = {
                PathModified = "/run/current-system";
                Unit = "soyo-activation-trace.service";
              };
            };

            # Health trace
            systemd.services.soyo-health-trace = {
              description = "Periodic health checks as traces";
              after = [
                "multi-user.target"
                "tempo.service"
              ];
              wants = [ "tempo.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  let
                    tracer = pkgs.writeShellApplication {
                      name = "soyo-health-trace";
                      runtimeInputs = [
                        pkgs.curl
                        pkgs.jq
                        pkgs.util-linux
                      ];
                      excludeShellChecks = [ "SC2016" ];
                      text = ''
                        set -eu
                        TRACE_ID=$(uuidgen | tr 'A-F' 'a-f' | tr -d -)
                        ROOT_SPAN_ID=$(uuidgen | tr 'A-F' 'a-f' | tr -d - | cut -c1-16)
                        ROOT_START_NS=$(date +%s%N)

                        run_check() {
                          local name="$1" start end status_code rc span_id
                          shift
                          start=$(date +%s%N)
                          status_code=0
                          rc=0
                          "$@" >/dev/null 2>&1 || { status_code=2; rc=$?; }
                          end=$(date +%s%N)
                          span_id=$(uuidgen | tr 'A-F' 'a-f' | tr -d - | cut -c1-16)
                          ${pkgs.jq}/bin/jq -nc \
                            --arg trace_id "$TRACE_ID" \
                            --arg root_span_id "$ROOT_SPAN_ID" \
                            --arg span_id "$span_id" \
                            --arg name "$name" \
                            --argjson status_code "$status_code" \
                            --arg rc "$rc" \
                            --arg start "$start" \
                            --arg end "$end" \
                            '{
                              traceId: $trace_id, spanId: $span_id,
                              parentSpanId: $root_span_id,
                              name: $name, kind: 2,
                              startTimeUnixNano: $start, endTimeUnixNano: $end,
                              status: {code: $status_code},
                              attributes: [
                                {key: "check", value: {stringValue: $name}},
                                {key: "healthy", value: {boolValue: ($status_code == 0)}},
                                {key: "return_code", value: {intValue: $rc}}
                              ]
                            }'
                        }

                        SPANS=$(
                          (run_check "disk-usage" btrfs filesystem usage -b / || true)
                          echo ','
                          (run_check "systemd-health" systemctl is-active --quiet multi-user.target)
                          echo ','
                          (run_check "memory-free" sh -c "awk '/MemAvailable/{exit !(\$2 > 0)}' /proc/meminfo")
                          echo ','
                          (run_check "zram-usage" sh -c "awk '/swap/ {found=1} END {exit found ? 0 : 1}' /proc/swaps")
                        )

                        ROOT_END_NS=$(date +%s%N)
                        ROOT_SPAN=$(${pkgs.jq}/bin/jq -nc \
                          --arg trace_id "$TRACE_ID" \
                          --arg span_id "$ROOT_SPAN_ID" \
                          --arg start "$ROOT_START_NS" \
                          --arg end "$ROOT_END_NS" \
                          '{
                            traceId: $trace_id, spanId: $span_id,
                            name: "soyo-health", kind: 2,
                            startTimeUnixNano: $start, endTimeUnixNano: $end
                          }')

                        ${pkgs.jq}/bin/jq -nc \
                          --argjson root_span "$ROOT_SPAN" \
                          --argjson spans "$(${pkgs.jq}/bin/jq -n "[$SPANS]" -c)" \
                          '{
                            resourceSpans: [{
                              resource: {attributes: [
                                {key: "service.name", value: {stringValue: "soyo-health"}},
                                {key: "host.name", value: {stringValue: "soyo"}}
                              ]},
                              scopeSpans: [{
                                scope: {name: "health"},
                                spans: ([$root_span] + $spans)
                              }]
                            }]
                          }' \
                          | ${pkgs.curl}/bin/curl -fsS -o /dev/null -X POST \
                            -H 'Content-Type: application/json' \
                            -d @- http://localhost:4318/v1/traces
                      '';
                    };
                  in
                  "${tracer}/bin/soyo-health-trace";
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 19;
              };
            };
            systemd.timers.soyo-health-trace = {
              description = "Periodic health check trace";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "5m";
                OnUnitActiveSec = "10m";
                RandomizedDelaySec = "60";
                Persistent = true;
              };
            };
          })

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
