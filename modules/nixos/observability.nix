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

            # Loki: lightweight log storage. Local filesystem backend, no S3
            # needed at this scale. Loopback-only, sits next to Grafana.
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
                # Without this, Loki probes localhost:8500 (Consul) and
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
              loki.relabel "journal_drilldown" {
                forward_to = []

                // Fallback service name for logs without a systemd unit.
                rule {
                  source_labels = ["__journal_syslog_identifier"]
                  regex         = "(.+)"
                  target_label  = "service_name"
                }

                // Prefer the systemd unit when present so Drilldown groups by
                // the actual service instead of lumping the whole journal into
                // one synthetic bucket.
                rule {
                  source_labels = ["__journal__systemd_unit"]
                  regex         = "(.+)"
                  target_label  = "service_name"
                }

                // Grafana's volume histogram groups by level/detected_level.
                // Some journal entries arrive without a usable priority, so we
                // seed a fallback and override it when journald provides one.
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

              // Ship systemd journal to local Loki
              loki.source.journal "soyo" {
                // This only applies when the positions file is missing, for
                // example after a deliberate state wipe. Keep the backfill
                // short so Drilldown reaches recent logs quickly again.
                max_age       = "30m"
                forward_to    = [loki.write.local_loki.receiver]
                relabel_rules = loki.relabel.journal_drilldown.rules
                labels        = {
                  job  = "systemd-journal",
                  host = "soyo",
                }
              }

              // Push to local Loki on loopback
              loki.write "local_loki" {
                endpoint {
                  url = "http://localhost:3100/loki/api/v1/push"
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
                      value = "localhost:9153";
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
                      value = "localhost:4000";
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
                      value = "localhost:9100";
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
                # Grafana gets two first-party dashboards:
                # - Fleet Overview is the default landing page once more hosts join.
                # - Soyo Control Plane stays the DNS/DHCP drilldown for the appliance itself.
                fleetJson = pkgs.writeText "fleet-overview.json" (
                  let
                    ds = "soyo-prometheus";
                    refIds = [
                      "A"
                      "B"
                    ];

                    mkGrid = x: y: w: h: {
                      inherit
                        x
                        y
                        w
                        h
                        ;
                    };

                    mkTarget =
                      refId: expr: legendFormat:
                      {
                        inherit
                          expr
                          refId
                          ;
                        datasource = {
                          type = "prometheus";
                          uid = ds;
                        };
                      }
                      // lib.optionalAttrs (legendFormat != null) { inherit legendFormat; };

                    mkPanel = id: x: y: w: h: type: title: {
                      inherit
                        id
                        type
                        title
                        ;
                      gridPos = mkGrid x y w h;
                    };

                    mkText =
                      {
                        id,
                        x,
                        y,
                        w,
                        h,
                        title,
                        content,
                      }:
                      mkPanel id x y w h "text" title
                      // {
                        options = {
                          mode = "markdown";
                          inherit content;
                        };
                        transparent = true;
                      };

                    mkStat =
                      {
                        id,
                        x,
                        y,
                        w,
                        h,
                        title,
                        expr,
                        unit ? "none",
                        description ? null,
                        thresholds ? null,
                        mappings ? [ ],
                        decimals ? null,
                      }:
                      mkPanel id x y w h "stat" title
                      // {
                        fieldConfig.defaults = {
                          inherit unit;
                          color.mode = "thresholds";
                        }
                        // lib.optionalAttrs (description != null) { inherit description; }
                        // lib.optionalAttrs (decimals != null) { inherit decimals; }
                        // lib.optionalAttrs (thresholds != null) {
                          thresholds = {
                            mode = "absolute";
                            steps = thresholds;
                          };
                        }
                        // lib.optionalAttrs (mappings != [ ]) { inherit mappings; };
                        options = {
                          colorMode = "backgroundSolid";
                          graphMode = "area";
                          justifyMode = "center";
                          orientation = "auto";
                          reduceOptions = {
                            calcs = [ "lastNotNull" ];
                            fields = "";
                            values = false;
                          };
                          textMode = "value";
                          wideLayout = true;
                        };
                        targets = [ (mkTarget "A" expr null) ];
                      };

                    mkTimeseries =
                      {
                        id,
                        x,
                        y,
                        w,
                        h,
                        title,
                        unit,
                        targets,
                        description ? null,
                      }:
                      mkPanel id x y w h "timeseries" title
                      // {
                        fieldConfig.defaults = {
                          inherit unit;
                          color.mode = "palette-classic";
                          custom = {
                            axisBorderShow = false;
                            drawStyle = "line";
                            fillOpacity = 12;
                            lineInterpolation = "smooth";
                            lineWidth = 2;
                            pointSize = 3;
                            showPoints = "never";
                            spanNulls = true;
                          };
                        }
                        // lib.optionalAttrs (description != null) { inherit description; };
                        options = {
                          legend = {
                            calcs = [
                              "lastNotNull"
                              "mean"
                            ];
                            displayMode = "table";
                            placement = "bottom";
                            showLegend = true;
                          };
                          tooltip = {
                            mode = "multi";
                            sort = "desc";
                          };
                        };
                        targets = lib.imap0 (
                          i: target: mkTarget (builtins.elemAt refIds i) target.expr target.legend
                        ) targets;
                      };
                  in
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
                );
                homeJson = pkgs.writeText "soyo-home.json" (
                  let
                    ds = "soyo-prometheus";
                    refIds = [
                      "A"
                      "B"
                      "C"
                      "D"
                    ];

                    mkGrid = x: y: w: h: {
                      inherit
                        x
                        y
                        w
                        h
                        ;
                    };

                    mkTarget =
                      refId: expr: legendFormat:
                      {
                        inherit
                          expr
                          refId
                          ;
                        datasource = {
                          type = "prometheus";
                          uid = ds;
                        };
                      }
                      // lib.optionalAttrs (legendFormat != null) { inherit legendFormat; };

                    mkPanel = id: x: y: w: h: type: title: {
                      inherit
                        id
                        type
                        title
                        ;
                      gridPos = mkGrid x y w h;
                    };

                    mkText =
                      {
                        id,
                        x,
                        y,
                        w,
                        h,
                        title,
                        content,
                      }:
                      mkPanel id x y w h "text" title
                      // {
                        options = {
                          mode = "markdown";
                          inherit content;
                        };
                        transparent = true;
                      };

                    mkStat =
                      {
                        id,
                        x,
                        y,
                        w,
                        h,
                        title,
                        expr,
                        unit ? "none",
                        description ? null,
                        thresholds ? null,
                        mappings ? [ ],
                        decimals ? null,
                      }:
                      mkPanel id x y w h "stat" title
                      // {
                        fieldConfig.defaults = {
                          inherit unit;
                          color.mode = "thresholds";
                        }
                        // lib.optionalAttrs (description != null) { inherit description; }
                        // lib.optionalAttrs (decimals != null) { inherit decimals; }
                        // lib.optionalAttrs (thresholds != null) {
                          thresholds = {
                            mode = "absolute";
                            steps = thresholds;
                          };
                        }
                        // lib.optionalAttrs (mappings != [ ]) { inherit mappings; };
                        options = {
                          colorMode = "backgroundSolid";
                          graphMode = "area";
                          justifyMode = "center";
                          orientation = "auto";
                          reduceOptions = {
                            calcs = [ "lastNotNull" ];
                            fields = "";
                            values = false;
                          };
                          textMode = "value";
                          wideLayout = true;
                        };
                        targets = [ (mkTarget "A" expr null) ];
                      };

                    mkTimeseries =
                      {
                        id,
                        x,
                        y,
                        w,
                        h,
                        title,
                        unit,
                        targets,
                        description ? null,
                      }:
                      mkPanel id x y w h "timeseries" title
                      // {
                        fieldConfig.defaults = {
                          inherit unit;
                          color.mode = "palette-classic";
                          custom = {
                            axisBorderShow = false;
                            drawStyle = "line";
                            fillOpacity = 16;
                            lineInterpolation = "smooth";
                            lineWidth = 2;
                            pointSize = 3;
                            showPoints = "never";
                            spanNulls = true;
                          };
                        }
                        // lib.optionalAttrs (description != null) { inherit description; };
                        options = {
                          legend = {
                            calcs = [
                              "lastNotNull"
                              "mean"
                            ];
                            displayMode = "table";
                            placement = "bottom";
                            showLegend = true;
                          };
                          tooltip = {
                            mode = "multi";
                            sort = "desc";
                          };
                        };
                        targets = lib.imap0 (
                          i: target: mkTarget (builtins.elemAt refIds i) target.expr target.legend
                        ) targets;
                      };

                    fsUsed =
                      mountpoint:
                      ''100 * (1 - (node_filesystem_avail_bytes{mountpoint="${mountpoint}",fstype!=""} / node_filesystem_size_bytes{mountpoint="${mountpoint}",fstype!=""}))'';

                    persistFree = ''100 * (node_filesystem_avail_bytes{mountpoint="/persist",fstype!=""} / node_filesystem_size_bytes{mountpoint="/persist",fstype!=""})'';

                    blockRate30m = ''100 * sum(rate(blocky_query_total{reason="BLOCKED"}[30m])) / clamp_min(sum(rate(blocky_query_total[30m])), 0.001)'';

                    cacheHitRate30m = "100 * sum(rate(dnsmasq_cache_hits[30m])) / clamp_min(sum(rate(dnsmasq_cache_hits[30m])) + sum(rate(dnsmasq_cache_misses[30m])), 0.001)";

                    blockRate5m = ''100 * sum(rate(blocky_query_total{reason="BLOCKED"}[5m])) / clamp_min(sum(rate(blocky_query_total[5m])), 0.001)'';

                    cacheHitRate5m = "100 * sum(rate(dnsmasq_cache_hits[5m])) / clamp_min(sum(rate(dnsmasq_cache_hits[5m])) + sum(rate(dnsmasq_cache_misses[5m])), 0.001)";
                  in
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
                  dashboards.default_home_dashboard_path = "${fleetJson}";
                };
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
                      '';
                    }
                    {
                      name = "soyo";
                      type = "file";
                      folder = "soyo";
                      options.path = pkgs.runCommand "soyo-grafana-dashboards" { } ''
                        mkdir -p $out
                        cp ${homeJson} $out/001-soyo-control-plane.json
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
                        # in 13.0.3, old API stays operative. Grafana does not
                        # treat POST as an upsert, so we delete each managed UID
                        # first to replace stale rules from older revisions.
                        delete_rule() {
                          local uid="$1" status
                          status=$(command curl -sS -u "$AUTH" -o /dev/null -w '%{http_code}'                             -X DELETE "$BASE/api/v1/provisioning/alert-rules/$uid")
                          [ "$status" = 200 ] || [ "$status" = 202 ] || [ "$status" = 404 ]
                        }

                        post_rule() {
                          local uid="$1"
                          delete_rule "$uid"
                          ${pkgs.jq}/bin/jq -nc                             --arg uid "$uid" --arg title "$2"                             --arg expr "$3" --arg for "$4"                             --arg noData "$5" --arg summary "$6"                             '{uid: $uid, title: $title,
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
                              isPaused: false}'                             | curl -X POST -H 'Content-Type: application/json'                               -d @- "$BASE/api/v1/provisioning/alert-rules"
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

            # preservation owns the top-level persisted directories; tmpfiles
            # only creates Tempo's generator subdirs underneath that owned tree.
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

            # Tempo: distributed tracing backend. Single-binary mode for
            # single-host scale — no S3, no memberlist, no complex ring setup.
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

                # Metrics-generator: computes span metrics for TraceQL rate()
                # and service graph queries. Enabled even in single-binary mode
                # — without it, `rate()` returns "empty ring".
                metrics_generator = {
                  storage.path = "/var/lib/tempo/generator-wal";
                  # TraceQL metrics over recent traces come from the local-blocks
                  # processor, which needs its own trace WAL separate from the
                  # generator's metric WAL.
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
                                  traceId: $trace_id,
                                  spanId: $span_id,
                                  name: "systemd-boot",
                                  kind: 2,
                                  startTimeUnixNano: $start_ns,
                                  endTimeUnixNano: $end_ns,
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

            # Activation tracer: watches /run/current-system for changes and
            # pushes a trace each time nixos-rebuild activates a new generation.
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
                                  traceId: $trace_id,
                                  spanId: $span_id,
                                  name: ("nixos-activation-" + $gen),
                                  kind: 2,
                                  startTimeUnixNano: $start_ns,
                                  endTimeUnixNano: $now_ns,
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
            # Path unit: triggers activation trace when /run/current-system changes
            systemd.paths.soyo-activation-trace = {
              description = "Watch for NixOS activation";
              wantedBy = [ "multi-user.target" ];
              pathConfig = {
                PathModified = "/run/current-system";
                Unit = "soyo-activation-trace.service";
              };
            };

            # Health check tracer: runs periodically, checks disk, systemd
            # state, memory, zram, and pushes results as a trace.
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
                              traceId: $trace_id,
                              spanId: $span_id,
                              parentSpanId: $root_span_id,
                              name: $name,
                              kind: 2,
                              startTimeUnixNano: $start,
                              endTimeUnixNano: $end,
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
                            traceId: $trace_id,
                            spanId: $span_id,
                            name: "soyo-health",
                            kind: 2,
                            startTimeUnixNano: $start,
                            endTimeUnixNano: $end
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
        ]
      );
    };
}
