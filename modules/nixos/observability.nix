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

      # --- grafana-dashboards.nix patterns ---
      # Community dashboards use ${DS_PROMETHEUS} template variables that
      # only resolve during the Grafana import wizard. File provisioning
      # skips that wizard, so we replace the placeholders and remove the
      # variables from the templating list — adapted from:
      # https://github.com/blackheaven/grafana-dashboards.nix

      fetchDashboard =
        { id, hash }:
        pkgs.fetchurl {
          url = "https://grafana.com/api/dashboards/${toString id}/revisions/latest/download";
          sha256 = hash;
        };

      # Replace ${KEY} with value everywhere, then drop those template variables.
      # Handles three patterns:
      # 1. ${KEY} — datasource UIDs and JSON-embedded template refs
      # 2. "$key"  — bare PromQL template refs (quoted, in selector context)
      # 3. $key    — Grafana builtins like $__rate_interval (always → "4m")
      #    Community dashboards use this in PromQL range vectors, but
      #    Grafana resolves it to ~15s on short windows while Prometheus
      #    scrapes every 1m — rate(...[15s]) gets zero data. 4m gives
      #    enough samples without being too coarse.
      fillTemplating =
        {
          replacements,
          dashboard,
          tags ? [ ],
        }:
        let
          raw = builtins.fromJSON (builtins.readFile dashboard);
          templateNames = map (r: r.key) replacements;

          dolBracePairs = map (r: "\${${r.key}}") replacements;
          dolBraceValues = map (r: r.value) replacements;
          barePairs = map (r: "\"\$${r.key}\"") replacements;
          bareValues = map (r: "\"${r.value}\"") replacements;

          allPairs = dolBracePairs ++ barePairs ++ [ "$__rate_interval" ];
          allValues = dolBraceValues ++ bareValues ++ [ "4m" ];

          replaceStrings =
            x:
            if builtins.isString x then
              builtins.replaceStrings allPairs allValues x
            else if builtins.isList x then
              map replaceStrings x
            else if builtins.isAttrs x then
              lib.mapAttrsRecursive (_: replaceStrings) x
            else
              x;

          cleaned = replaceStrings raw;
          withoutTemplates = cleaned // {
            templating = cleaned.templating // {
              list = builtins.filter (v: !(builtins.elem v.name templateNames)) cleaned.templating.list;
            };
          };
          withTags = withoutTemplates // {
            inherit tags;
          };
        in
        pkgs.writeText "dashboard.json" (builtins.toJSON withTags);
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
              interfaces.enp1s0.allowedTCPPorts = lib.optionals grafanaCfg.enable [ 3000 ];
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
                analytics.reporting_enabled = false;

                server = {
                  http_listen_port = 3100;
                  http_listen_address = "127.0.0.1";
                  log_level = "warn";
                };

                # Single-node mode: inmemory ring, no replication.
                # Without this, Loki requires 2+ ingester replicas and rejects
                # writes with HTTP 500 ("at least 2 live replicas required").
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

                # Disable scheduler ring — single node doesn't need it.
                # Without this, Loki probes 127.0.0.1:8500 (Consul) and
                # the query API hangs indefinitely.
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
                  retention_period = "720h"; # 30 days
                  allow_structured_metadata = false;
                  ingestion_rate_mb = 12;
                  ingestion_burst_size_mb = 18;
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
                max_age    = "12h"
                forward_to = [loki.write.local_loki.receiver]
                labels     = {
                  job  = "systemd-journal",
                  host = "soyo",
                }
              }

              // Push to local Loki on loopback
              loki.write "local_loki" {
                endpoint {
                  url = "http://127.0.0.1:3100/loki/api/v1/push"
                }
              }
            '';

            services.grafana =
              let
                dnsmasqJson = fillTemplating {
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
                      value = "127.0.0.1:9153";
                    }
                  ];
                  tags = [
                    "dnsmasq"
                    "dhcp"
                    "dns"
                  ];
                  dashboard = fetchDashboard {
                    id = 18796;
                    hash = "1nn4nvbq7q2d4cbsmlr1796if3j6ndpyh0r19w6xy2iwxmxdx0a2";
                  };
                };
                blockyJson = fillTemplating {
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
                      value = "127.0.0.1:4000";
                    }
                  ];
                  tags = [
                    "blocky"
                    "dns"
                    "adblock"
                  ];
                  dashboard = fetchDashboard {
                    id = 13768;
                    hash = "0lci2a09ghmjab226m06shcmyxh11pqld0hkjv9ibv22fmrcw0w3";
                  };
                };
                nodeExporterJson = fillTemplating {
                  replacements = [
                    {
                      key = "ds_prometheus";
                      value = "soyo-prometheus";
                    }
                    {
                      key = "job";
                      value = "node";
                    }
                    {
                      key = "nodename";
                      value = "soyo";
                    }
                    {
                      key = "node";
                      value = "127.0.0.1:9100";
                    }
                  ];
                  tags = [
                    "linux"
                    "node-exporter"
                  ];
                  dashboard = fetchDashboard {
                    id = 1860;
                    hash = "11hrll7fm626ikbva5md4gm0rca537vp4xsxa9sxl1pk15s6nk0q";
                  };
                };
                homeJson = pkgs.writeText "soyo-home.json" (
                  builtins.toJSON {
                    title = "Soyo Home";
                    uid = "soyo-home";
                    tags = [ "home" ];
                    editable = false;
                    time = {
                      from = "now-12h";
                      to = "now";
                    };
                    refresh = "30s";
                    templating.list = [ ];
                    panels =
                      let
                        ds = "soyo-prometheus";
                        ts = x: y: w: h: t: e: f: {
                          gridPos = {
                            inherit
                              x
                              y
                              w
                              h
                              ;
                          };
                          type = "timeseries";
                          title = t;
                          fieldConfig.defaults = {
                            custom = {
                              fillOpacity = 10;
                              lineWidth = 1;
                            };
                            unit = f;
                          };
                          targets = [
                            {
                              expr = e;
                              datasource = {
                                type = "prometheus";
                                uid = ds;
                              };
                              refId = "A";
                            }
                          ];
                        };
                        g = x: y: w: h: t: e: f: {
                          gridPos = {
                            inherit
                              x
                              y
                              w
                              h
                              ;
                          };
                          type = "stat";
                          title = t;
                          fieldConfig.defaults.unit = f;
                          options.reduceOptions = {
                            calcs = [ "lastNotNull" ];
                          };
                          targets = [
                            {
                              expr = e;
                              datasource = {
                                type = "prometheus";
                                uid = ds;
                              };
                              refId = "A";
                            }
                          ];
                        };
                        st = x: y: w: h: t: e: f: d: {
                          gridPos = {
                            inherit
                              x
                              y
                              w
                              h
                              ;
                          };
                          type = "stat";
                          title = t;
                          fieldConfig.defaults = {
                            unit = f;
                            description = d;
                          };
                          options = {
                            reduceOptions = {
                              calcs = [ "lastNotNull" ];
                            };
                            textMode = "value";
                          };
                          targets = [
                            {
                              expr = e;
                              datasource = {
                                type = "prometheus";
                                uid = ds;
                              };
                              refId = "A";
                            }
                          ];
                        };
                      in
                      [
                        (ts 0 0 24 10 "CPU Usage %"
                          ''100 - avg by (mode) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100''
                          "percent"
                        )
                        (ts 0 10 24 10 "Memory" "node_memory_MemAvailable_bytes" "bytes")
                        (st 0 20 8 4 "Uptime" "node_time_seconds - node_boot_time_seconds" "s" "Seconds since last boot")
                        (g 8 20 8 4 "/ Disk"
                          ''100 - (node_filesystem_avail_bytes{mountpoint="/",fstype!=""} / node_filesystem_size_bytes{mountpoint="/",fstype!=""}) * 100''
                          "percent"
                        )
                        (g 16 20 8 4 "/persist"
                          ''100 - (node_filesystem_avail_bytes{mountpoint="/persist",fstype!=""} / node_filesystem_size_bytes{mountpoint="/persist",fstype!=""}) * 100''
                          "percent"
                        )
                        (ts 0 24 24 10 "Network Traffic" ''rate(node_network_receive_bytes_total{device="enp1s0"}[5m])''
                          "Bps"
                        )
                        (ts 0 34 24 10 "DNS Queries (dnsmasq)" "rate(dnsmasq_servers_queries[5m])" "short")
                        (st 0 44 8 4 "DNS Cache Hit Rate"
                          "(dnsmasq_cache_hits / (dnsmasq_cache_hits + dnsmasq_cache_misses)) * 100"
                          "percent"
                          "% of queries served from cache"
                        )
                        (ts 0 48 24 10 "Blocky Queries" "rate(blocky_query_total[5m])" "short")
                        (ts 0 58 24 10 "Blocked Queries" ''rate(blocky_query_total{reason="BLOCKED"}[5m])'' "short")
                        (st 0 68 8 4 "DHCP Leases" "dnsmasq_leases" "none" "Active DHCP leases")
                        (st 8 68 8 4 "Blocked Total" ''blocky_query_total{reason="BLOCKED"}'' "none"
                          "Total blocked queries since start"
                        )
                      ];
                  }
                );
              in
              {
                enable = true;
                settings = {
                  server = {
                    http_addr = "0.0.0.0";
                    http_port = 3000;
                    domain = grafanaCfg.domain;
                    root_url = "http://${grafanaCfg.domain}:3000";
                  };
                  analytics.reporting_enabled = false;
                  grafana_news.new_news_enabled = false;
                  # Required by Grafana 13+.
                  security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
                  # Admin password from agenix-encrypted secret.
                  security.admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
                  unified_alerting.enabled = true;
                  dashboards.default_home_dashboard_path = "${homeJson}";
                };
                provision.datasources.settings = {
                  apiVersion = 1;
                  datasources = [
                    {
                      name = "Prometheus";
                      type = "prometheus";
                      access = "proxy";
                      url = "http://127.0.0.1:9090";
                      uid = "soyo-prometheus";
                      isDefault = true;
                    }
                    {
                      name = "Loki";
                      type = "loki";
                      access = "proxy";
                      url = "http://127.0.0.1:3100";
                      uid = "soyo-loki";
                      jsonData.httpHeaderName1 = "X-Scope-OrgID";
                      secureJsonData.httpHeaderValue1 = "fake";
                    }
                    {
                      name = "Tempo";
                      type = "tempo";
                      access = "proxy";
                      url = "http://127.0.0.1:3200";
                      uid = "soyo-tempo";
                    }
                  ];
                };
                provision.dashboards.settings = {
                  apiVersion = 1;
                  providers = [
                    {
                      name = "soyo";
                      type = "file";
                      folder = "soyo";
                      options.path = pkgs.runCommand "soyo-grafana-dashboards" { } ''
                        mkdir -p $out
                        cp ${homeJson} $out/001-home.json
                        cp ${dnsmasqJson} $out/dnsmasq.json
                        cp ${blockyJson} $out/blocky.json
                        cp ${nodeExporterJson} $out/node-exporter-full.json
                      '';
                    }
                  ];
                };
                # Alert rules provisioned via the Grafana API at boot
                # (see grafana-alert-setup.service below).
              };

            # Grafana alert setup: runs after boot, provisions contact points,
            # notification policies, and alert rules via the Grafana HTTP API.
            # Secrets (ntfy topic/token, admin password) are read from agenix
            # runtime paths — no secrets leaked into the Nix store.
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

                        # Folder: alert rules need a folder UID in Grafana 13.
                        # Create if absent, then PUT to enforce the title
                        # (Grafana ignores title changes on POST for existing folders).
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

                        # Contact point: ntfy webhook with template-based rendering.
                        # Grafana sends raw alert JSON; ntfy extracts title/message
                        # from the payload via its Go template engine.
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

                        # Notification policy: route all alerts to ntfy
                        provision_policy() {
                          ${pkgs.jq}/bin/jq -nc \
                            '{receiver: "ntfy", group_by: ["severity", "team"],
                              group_wait: "30s", group_interval: "5m",
                              repeat_interval: "4h", routes: []}' \
                            | curl -X PUT -H 'Content-Type: application/json' \
                              -d @- "$BASE/api/v1/provisioning/policies"
                        }

                        # Alert rules (Grafana 13 /api/v1: the new /apis/v0alpha1 is broken
                        # in 13.0.3, old API stays operative. Requires ruleGroup + orgID.)
                        post_rule() {
                          ${pkgs.jq}/bin/jq -nc \
                            --arg uid "$1" --arg title "$2" \
                            --arg expr "$3" --arg for "$4" \
                            --arg noData "$5" --arg summary "$6" \
                            '{uid: $uid, title: $title,
                              folderUID: "soyo", ruleGroup: "soyo", orgID: 1,
                              condition: "A", noDataState: $noData,
                              execErrState: "Error", for: $for,
                              data: [{
                                refId: "A",
                                relativeTimeRange: {from: 600, to: 0},
                                datasourceUid: "prometheus",
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

            # Resource isolation: Grafana, Loki, Prometheus, and Alloy are guest
            # services — prevent them from starving Blocky or dnsmasq.
            systemd.services.grafana.serviceConfig = {
              MemoryMax = "256M";
              CPUQuota = "20%";
              Nice = 10;
            };

            # Ensure persisted data dirs have correct ownership for their service users.
            # The preservation module bind-mounts /persist/var/lib/<name> onto /var/lib/<name>;
            # without explicit ownership, the source dir is owned by root and the service user
            # can't write. tmpfiles fixes this at boot.
            systemd.tmpfiles.rules = [
              "d /persist/var/lib/grafana 0750 grafana grafana -"
              "d /persist/var/lib/loki 0750 loki loki -"
              "d /persist/var/lib/tempo 0750 tempo tempo -"
              "d /persist/var/lib/tempo/generator-wal 0750 tempo tempo -"
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

            # Tempo: distributed tracing backend. Single-binary mode for
            # single-host scale — no S3, no memberlist, no complex ring setup.
            services.tempo = {
              enable = true;
              settings = {
                target = "all";

                server = {
                  http_listen_port = 3200;
                  http_listen_address = "127.0.0.1";
                  grpc_listen_port = 4319;
                  grpc_listen_address = "127.0.0.1";
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

                querier.frontend_worker.frontend_address = "127.0.0.1:9095";
                query_frontend = {
                  max_outstanding_per_tenant = 2000;
                };

                storage.trace = {
                  backend = "local";
                  local.path = "/var/lib/tempo/traces";
                  wal.path = "/var/lib/tempo/wal";
                };

                # Metrics-generator: computes span metrics for TraceQL rate()
                # and service graph queries. Enabled even in single-binary mode
                # — without it, `rate()` returns "empty ring".
                metrics_generator = {
                  storage.path = "/var/lib/tempo/generator-wal";
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
                };
              };
            };

            # Tempo needs a static UID across boots — DynamicUser (nixpkgs
            # default) reassigns UIDs, breaking ownership of persisted data.
            users.users.tempo = {
              description = "Tempo trace storage user";
              group = "tempo";
              isSystemUser = true;
            };
            users.groups.tempo = { };
            systemd.services.tempo.serviceConfig.DynamicUser = lib.mkForce false;

            # Boot trace generator: runs once after each boot, captures
            # systemd-analyze blame data as an OTLP trace, pushes to Tempo.
            systemd.services.soyo-boot-trace = {
              description = "Generate boot trace from systemd-analyze";
              after = [ "multi-user.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  let
                    tracer = pkgs.writeShellApplication {
                      name = "soyo-boot-trace";
                      runtimeInputs = [
                        pkgs.curl
                        pkgs.jq
                        pkgs.util-linux
                      ];
                      text = ''
                        set -eu
                        TRACE_ID=$(uuidgen | tr -d -)
                        systemd-analyze blame 2>/dev/null \
                          | ${pkgs.jq}/bin/jq -nRc \
                            --arg trace_id "$TRACE_ID" \
                            '[limit(20; inputs | split(" ") | last | select(. != ""))] as $units |
                             {
                               resourceSpans: [{
                                 resource: {attributes: [
                                   {key: "service.name", value: {stringValue: "systemd-boot"}},
                                   {key: "host.name", value: {stringValue: "soyo"}}
                                 ]},
                                 scopeSpans: [{
                                   scope: {name: "systemd-analyze"},
                                   spans: [$units[] | {
                                     traceId: $trace_id,
                                     spanId: (.[0:16]),
                                     name: .,
                                     kind: 2
                                   }]
                                 }]
                               }]
                             }' \
                          | ${pkgs.curl}/bin/curl -sS -o /dev/null -X POST \
                            -H 'Content-Type: application/json' \
                            -d @- http://127.0.0.1:4318/v1/traces
                      '';
                    };
                  in
                  "${tracer}/bin/soyo-boot-trace";
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 19;
              };
            };

            # Activation tracer: watches /run/current-system for changes and
            # pushes a trace each time nixos-rebuild activates a new generation.
            systemd.services.soyo-activation-trace = {
              description = "Trace nixos-rebuild activation";
              after = [ "multi-user.target" ];
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
                        TRACE_ID=$(uuidgen | tr -d -)
                        SPAN_ID=$(uuidgen | tr -d - | cut -c1-16)
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
                                  startTimeUnixNano: $start_ns,
                                  endTimeUnixNano: $now_ns,
                                  attributes: [
                                    {key: "generation", value: {stringValue: $gen}}
                                  ]
                                }]
                              }]
                            }]
                          }' \
                          | ${pkgs.curl}/bin/curl -sS -o /dev/null -X POST \
                            -H 'Content-Type: application/json' \
                            -d @- http://127.0.0.1:4318/v1/traces
                      '';
                    };
                  in
                  "${tracer}/bin/soyo-activation-trace";
                MemoryMax = "32M";
                CPUQuota = "5%";
                Nice = 19;
              };
            };
            # Path unit: triggers activation trace when /run/current-system changes
            systemd.paths.soyo-activation-trace = {
              description = "Watch for NixOS activation";
              wantedBy = [ "multi-user.target" ];
              pathConfig = {
                PathModified = "/run/current-system";
                Unit = "soyo-activation-trace.service";
              };
            };

            # Health check tracer: runs hourly, checks disk, system state,
            # memory, zram, and pushes results as a trace.
            systemd.services.soyo-health-trace = {
              description = "Periodic health checks as traces";
              after = [ "multi-user.target" ];
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
                        TRACE_ID=$(uuidgen | tr -d -)

                        run_check() {
                          local name="$1" start end ok rc
                          shift
                          start=$(date +%s%N)
                          ok=0; rc=0
                          "$@" >/dev/null 2>&1 || { ok=2; rc=$?; }
                          end=$(date +%s%N)
                          ${pkgs.jq}/bin/jq -nc \
                            --arg name "$name" \
                            --argjson ok "$ok" \
                            --arg rc "$rc" \
                            --arg start "$start" \
                            --arg end "$end" \
                            '{
                              name: $name, kind: 2,
                              startTimeUnixNano: $start,
                              endTimeUnixNano: $end,
                              status: {code: $ok},
                              attributes: [
                                {key: "check", value: {stringValue: $name}},
                                {key: "healthy", value: {boolValue: ($ok == 0)}},
                                {key: "return_code", value: {intValue: $rc}}
                              ]
                            }'
                        }

                        SPANS=$(
                          (run_check "disk-usage" btrfs filesystem usage -b / 2>/dev/null || true)
                          echo ','
                          (run_check "systemd-health" systemctl is-active --quiet multi-user.target)
                          echo ','
                          (run_check "memory-free" awk '/MemAvailable/{print $2}' /proc/meminfo)
                          echo ','
                          (run_check "zram-usage" awk '/swap/ {s+=$2} END {print s}' /proc/swaps)
                        )

                        ${pkgs.jq}/bin/jq -nc \
                          --arg trace_id "$TRACE_ID" \
                          --argjson spans "$(${pkgs.jq}/bin/jq -n "[$SPANS]" -c)" \
                          '{
                            resourceSpans: [{
                              resource: {attributes: [
                                {key: "service.name", value: {stringValue: "soyo-health"}},
                                {key: "host.name", value: {stringValue: "soyo"}}
                              ]},
                              scopeSpans: [{
                                scope: {name: "health"},
                                spans: $spans
                              }]
                            }]
                          }' \
                          | ${pkgs.curl}/bin/curl -sS -o /dev/null -X POST \
                            -H 'Content-Type: application/json' \
                            -d @- http://127.0.0.1:4318/v1/traces
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
              description = "Hourly health check trace";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "hourly";
                RandomizedDelaySec = "120";
                Persistent = true;
              };
            };
          })
        ]
      );
    };
}
