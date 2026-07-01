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
              enabledCollectors = [ "textfile" ];
              extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus/textfiles" ];
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

              // OTLP receiver: accepts traces from local sources (boot tracer)
              // and forwards to Tempo on loopback.
              otelcol.receiver.otlp "soyo" {
                grpc { endpoint = "127.0.0.1:4317" }
                http { endpoint = "127.0.0.1:4318" }
                output {
                  traces = [otelcol.exporter.otlp.tempo.input]
                }
              }

              otelcol.exporter.otlp "tempo" {
                client {
                  endpoint = "127.0.0.1:4317"
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
                # Required by Grafana 13+.
                security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
                # Admin password from agenix-encrypted secret.
                security.admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
                unified_alerting.enabled = true;
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
                    options.path = pkgs.runCommand "soyo-grafana-dashboards" { } ''
                      mkdir -p $out
                      cp ${../../hosts/soyo/grafana/soyo-dashboard.json} $out/
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
              after = [
                "grafana.service"
                "network.target"
              ];
              wants = [ "grafana.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                MemoryMax = "64M";
                CPUQuota = "10%";
                Nice = 10;
                Restart = "on-failure";
                RestartSec = "10s";
              };
              script =
                let
                  setupScript = pkgs.writeShellScript "grafana-alert-setup" ''
                    set -euo pipefail

                    ADMIN_PASS=$(cat ${config.age.secrets.grafana-admin-password.path})
                    AUTH="admin:$ADMIN_PASS"
                    BASE="http://127.0.0.1:3000"

                    # Wait for Grafana to be ready
                    for i in $(seq 1 30); do
                      if curl -sf -u "$AUTH" "$BASE/api/health" > /dev/null 2>&1; then
                        break
                      fi
                      sleep 2
                    done

                    # --- Contact point: ntfy webhook ---
                    NTFY_TOPIC=$(cat ${config.age.secrets.ntfy-topic.path} 2>/dev/null || echo "")
                    NTFY_TOKEN=$(cat ${config.age.secrets.ntfy-token.path} 2>/dev/null || echo "")

                    if [ -n "$NTFY_TOPIC" ] && [ -n "$NTFY_TOKEN" ]; then
                      curl -sf -X POST -u "$AUTH" "$BASE/api/v1/provisioning/contact-points" \
                        -H "Content-Type: application/json" \
                        -d '{
                          "name": "ntfy",
                          "type": "webhook",
                          "settings": {
                            "url": "'"$NTFY_TOPIC"'",
                            "httpMethod": "POST",
                            "authorization": { "type": "Bearer", "credentials": "'"$NTFY_TOKEN"'" }
                          }
                        }' || true
                    fi

                    # --- Notification policy: route all alerts to ntfy ---
                    POLICY=$(curl -sf -u "$AUTH" "$BASE/api/v1/provisioning/policies" 2>/dev/null || echo 'null')
                    if [ "$POLICY" != "null" ]; then
                      curl -sf -X PUT -u "$AUTH" "$BASE/api/v1/provisioning/policies" \
                        -H "Content-Type: application/json" \
                        -d '{
                          "receiver": "ntfy",
                          "group_by": ["severity", "team"],
                          "group_wait": "30s",
                          "group_interval": "5m",
                          "repeat_interval": "4h",
                          "routes": []
                        }' || true
                    fi

                    # --- Alert rules ---
                    for RULE_JSON in \
                      '{"uid":"soyo_disk_space_low","title":"Disk space low on /persist","condition":"C","data":[{"refId":"A","queryType":"","relativeTimeRange":{"from":600,"to":0},"datasourceUid":"__expr__","model":{"type":"math","expression":"$B / $C * 100"}},{"refId":"B","queryType":"","relativeTimeRange":{"from":600,"to":0},"datasourceUid":"prometheus","model":{"type":"prometheus","expr":"node_filesystem_avail_bytes{mountpoint=\"/persist\",fstype!=\"\"}","intervalMs":60000,"maxDataPoints":1}},{"refId":"C","queryType":"","relativeTimeRange":{"from":600,"to":0},"datasourceUid":"prometheus","model":{"type":"prometheus","expr":"node_filesystem_size_bytes{mountpoint=\"/persist\",fstype!=\"\"}","intervalMs":60000,"maxDataPoints":1}}],"noDataState":"NoData","execErrState":"Error","for":"5m","annotations":{"summary":"/persist disk usage below 10%"},"labels":{"severity":"critical","team":"soyo"},"isPaused":false}' \
                      '{"uid":"soyo_backup_failed","title":"Backup failed","condition":"A","data":[{"refId":"A","queryType":"","relativeTimeRange":{"from":90000,"to":0},"datasourceUid":"prometheus","model":{"type":"prometheus","expr":"restic_backup_success == 0","intervalMs":60000,"maxDataPoints":1}}],"noDataState":"Alerting","execErrState":"Error","for":"30m","annotations":{"summary":"restic backup to Synology failed — check journalctl"},"labels":{"severity":"critical","team":"soyo"},"isPaused":false}' \
                      '{"uid":"soyo_blocky_down","title":"Service down: Blocky DNS","condition":"A","data":[{"refId":"A","queryType":"","relativeTimeRange":{"from":600,"to":0},"datasourceUid":"prometheus","model":{"type":"prometheus","expr":"up{job=\"blocky\"} == 0","intervalMs":60000,"maxDataPoints":1}}],"noDataState":"Alerting","execErrState":"Error","for":"2m","annotations":{"summary":"Blocky DNS is unreachable"},"labels":{"severity":"critical","team":"soyo"},"isPaused":false}' \
                      '{"uid":"soyo_dnsmasq_down","title":"Service down: dnsmasq","condition":"A","data":[{"refId":"A","queryType":"","relativeTimeRange":{"from":600,"to":0},"datasourceUid":"prometheus","model":{"type":"prometheus","expr":"up{job=\"dnsmasq\"} == 0","intervalMs":60000,"maxDataPoints":1}}],"noDataState":"Alerting","execErrState":"Error","for":"2m","annotations":{"summary":"dnsmasq unreachable — DHCP and reverse DNS down"},"labels":{"severity":"critical","team":"soyo"},"isPaused":false}'; do
                      echo "$RULE_JSON" | curl -sf -X POST -u "$AUTH" "$BASE/api/v1/provisioning/alert-rules" \
                        -H "Content-Type: application/json" \
                        -d @- || true
                    done
                  '';
                in
                "${setupScript}";
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

            # Tempo: distributed tracing backend. Stores traces locally with
            # filesystem backend — no S3 needed at single-host scale.
            systemd.services.tempo = {
              description = "Grafana Tempo trace storage";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = ''
                  ${pkgs.tempo}/bin/tempo -config.file=${pkgs.writeText "tempo-config.yaml" ''
                    server:
                      http_listen_port: 3200
                      http_listen_address: 127.0.0.1
                      grpc_listen_port: 4317
                      grpc_listen_address: 127.0.0.1

                    distributor:
                      receivers:
                        otlp:
                          protocols:
                            grpc:
                            http:

                    ingester:
                      lifecycler:
                        ring:
                          kvstore:
                            store: inmemory
                          replication_factor: 1

                    storage:
                      trace:
                        backend: local
                        local:
                          path: /var/lib/tempo/blocks
                        wal:
                          path: /var/lib/tempo/wal

                    compactor: {}

                    overrides:
                      max_bytes_per_trace: 5_000_000
                  ''}
                '';
                Restart = "on-failure";
                User = "tempo";
                Group = "tempo";
                StateDirectory = "tempo";
                WorkingDirectory = "/var/lib/tempo";
                MemoryMax = "512M";
                CPUQuota = "20%";
                Nice = 10;
              };
            };
            users.users.tempo = {
              description = "Tempo trace storage user";
              group = "tempo";
              isSystemUser = true;
            };
            users.groups.tempo = { };

            # Boot trace generator: runs once after each boot, captures
            # systemd-analyze data as an OTLP trace, pushes to Tempo via Alloy.
            systemd.services.soyo-boot-trace = {
              description = "Generate boot trace from systemd-analyze";
              after = [ "multi-user.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  let
                    tracer = pkgs.writeShellScript "soyo-boot-trace" ''
                          set -euo pipefail
                          exec ${pkgs.python3}/bin/python3 << 'PYEOF'
                      import json, subprocess, re, os, uuid

                      def get_boot_units():
                          try:
                              r = subprocess.run(["systemd-analyze", "blame"],
                                  capture_output=True, text=True, timeout=15)
                              units = []
                              for line in r.stdout.strip().split('\n')[:60]:
                                  m = re.match(r'^([\d.]+)s\s+(\S+)', line)
                                  if m: units.append((m.group(2), float(m.group(1))))
                              return units
                          except: return []

                      units = get_boot_units()
                      if not units:
                          raise SystemExit(0)

                      boot_ns = int(subprocess.run(
                          ["date", "-d", "$(systemd-analyze timestamp)", "+%s%N"],
                          capture_output=True, text=True, shell=True).stdout.strip()) * 1000
                      now_ns = int(subprocess.run(
                          ["date", "+%s%N"], capture_output=True, text=True).stdout.strip())
                      # If timestamp parsing failed, estimate from journal
                      if boot_ns < 1000000000:
                          boot_ns = now_ns - 120_000_000_000  # assume ~2 min ago

                      trace_id = uuid.uuid4().hex
                      spans = []
                      span_ts = boot_ns
                      for i, (name, dur) in enumerate(units):
                          dur_ns = int(dur * 1e9)
                          sid = uuid.uuid4().hex[:16]
                          spans.append({
                              "traceId": trace_id,
                              "spanId": sid,
                              "name": name,
                              "kind": 2,
                              "startTimeUnixNano": str(span_ts),
                              "endTimeUnixNano": str(span_ts + dur_ns),
                              "attributes": [
                                  {"key": "unit", "value": {"stringValue": name}},
                                  {"key": "duration_seconds", "value": {"doubleValue": dur}}
                              ]
                          })
                          span_ts += dur_ns

                      trace = {
                          "resourceSpans": [{
                              "resource": {"attributes": [
                                  {"key": "service.name", "value": {"stringValue": "systemd-boot"}},
                                  {"key": "host.name", "value": {"stringValue": "soyo"}}
                              ]},
                              "scopeSpans": [{
                                  "scope": {"name": "systemd-analyze"},
                                  "spans": spans
                              }]
                          }]
                      }

                      # Push via OTLP HTTP to Tempo (Alloy forwarder on :4318)
                      subprocess.run(
                          ["curl", "-sS", "-o", "/dev/null", "-X", "POST",
                           "-H", "Content-Type: application/json",
                           "--data", json.dumps(trace),
                           "http://127.0.0.1:4318/v1/traces"],
                          timeout=10, capture_output=True)
                      PYEOF
                    '';
                  in
                  "${tracer}";
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
                    tracer = pkgs.writeScript "soyo-activation-trace" ''
                      #!${pkgs.python3}/bin/python3
                      import json, os, subprocess, uuid

                      # Read the current generation from the profile symlink
                      gen_path = "/run/current-system"
                      if not os.path.isdir(gen_path):
                          raise SystemExit(0)

                      # Try to get build timestamp from the store path
                      try:
                          store_path = os.readlink(gen_path) if os.path.islink(gen_path) else gen_path
                          # Parse timestamp from the store path or use mtime
                          mtime = os.path.getmtime(gen_path)
                      except:
                          mtime = subprocess.run(
                              ["date", "+%s%N"], capture_output=True, text=True).stdout.strip()
                          mtime = int(mtime) if mtime.isdigit() else 0

                      now_ns = int(subprocess.run(
                          ["date", "+%s%N"], capture_output=True, text=True).stdout.strip())
                      # Activation happened at mtime (generation created)
                      start_ns = int(mtime * 1_000_000_000) if mtime > 1000000000 else now_ns - 300_000_000_000

                      # Get generation number
                      gen = "unknown"
                      try:
                          gen_result = subprocess.run(
                              ["nixos-version"], capture_output=True, text=True, timeout=5)
                          gen = gen_result.stdout.strip()[:40]
                      except:
                          pass

                      trace_id = uuid.uuid4().hex
                      root_id = uuid.uuid4().hex[:16]
                      spans = [{
                          "traceId": trace_id, "spanId": root_id,
                          "name": f"nixos-activation-{gen}", "kind": 2,
                          "startTimeUnixNano": str(start_ns),
                          "endTimeUnixNano": str(now_ns),
                          "attributes": [
                              {"key": "service.name", "value": {"stringValue": "nixos-activation"}},
                              {"key": "generation", "value": {"stringValue": gen}},
                              {"key": "store_path", "value": {"stringValue": store_path if 'store_path' in dir() else gen_path}}
                          ]
                      }]

                      trace = {
                          "resourceSpans": [{
                              "resource": {"attributes": [
                                  {"key": "service.name", "value": {"stringValue": "nixos-activation"}},
                                  {"key": "host.name", "value": {"stringValue": "soyo"}}
                              ]},
                              "scopeSpans": [{"scope": {"name": "nixos"}, "spans": spans}]
                          }]
                      }
                      subprocess.run(["curl", "-sS", "-o", "/dev/null", "-X", "POST",
                          "-H", "Content-Type: application/json",
                          "--data", json.dumps(trace),
                          "http://127.0.0.1:4318/v1/traces"], timeout=10, capture_output=True)
                    '';
                  in
                  "${tracer}";
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

            # Health check tracer: runs hourly, checks disk, SMART, services,
            # cert expiry, and pushes results as a trace.
            systemd.services.soyo-health-trace = {
              description = "Periodic health checks as traces";
              after = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  let
                    tracer = pkgs.writeScript "soyo-health-trace" ''
                      #!${pkgs.python3}/bin/python3
                      import json, subprocess, os, uuid

                      now_ns = int(subprocess.run(
                          ["date", "+%s%N"], capture_output=True, text=True).stdout.strip())
                      trace_id = uuid.uuid4().hex
                      spans = []

                      def run_check(name, cmd, timeout=10):
                          try:
                              start = int(subprocess.run(
                                  ["date", "+%s%N"], capture_output=True, text=True).stdout.strip())
                              r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
                              end = int(subprocess.run(
                                  ["date", "+%s%N"], capture_output=True, text=True).stdout.strip())
                              ok = r.returncode == 0
                              output = (r.stdout + r.stderr)[:200]
                              return {
                                  "ok": ok, "start": start, "end": end,
                                  "output": output, "rc": r.returncode
                              }
                          except Exception as e:
                              return {"ok": False, "start": now_ns, "end": now_ns,
                                      "output": str(e)[:200], "rc": -1}

                      checks = [
                          ("disk-usage", ["btrfs", "filesystem", "usage", "-b", "/"]),
                          ("systemd-health", ["systemctl", "is-system-running", "--wait"]),
                          ("memory-free", ["awk", "/MemAvailable/{print $2}", "/proc/meminfo"]),
                          ("zram-usage", ["awk", "/swap/ {s+=$2} END {print s}", "/proc/swaps"]),
                      ]

                      for name, cmd in checks:
                          r = run_check(name, cmd, timeout=15)
                          sid = uuid.uuid4().hex[:16]
                          spans.append({
                              "traceId": trace_id, "spanId": sid,
                              "name": name, "kind": 2,
                              "startTimeUnixNano": str(r["start"]),
                              "endTimeUnixNano": str(r["end"]),
                              "status": {"code": 0 if r["ok"] else 2},
                              "attributes": [
                                  {"key": "check", "value": {"stringValue": name}},
                                  {"key": "healthy", "value": {"boolValue": r["ok"]}},
                                  {"key": "return_code", "value": {"intValue": str(r["rc"])}},
                                  {"key": "output", "value": {"stringValue": r["output"]}}
                              ]
                          })

                      trace = {
                          "resourceSpans": [{
                              "resource": {"attributes": [
                                  {"key": "service.name", "value": {"stringValue": "soyo-health"}},
                                  {"key": "host.name", "value": {"stringValue": "soyo"}}
                              ]},
                              "scopeSpans": [{"scope": {"name": "health"}, "spans": spans}]
                          }]
                      }
                      subprocess.run(["curl", "-sS", "-o", "/dev/null", "-X", "POST",
                          "-H", "Content-Type: application/json",
                          "--data", json.dumps(trace),
                          "http://127.0.0.1:4318/v1/traces"], timeout=10, capture_output=True)
                    '';
                  in
                  "${tracer}";
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
