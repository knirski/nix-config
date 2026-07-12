{ lib, pkgs, ... }:
let
  hardening = import ../systemd-hardening.nix;
in
{
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
        processor = {
          local_blocks.filter_server_spans = false;
          span_metrics.enable_target_info = true;
          service_graphs = {
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

  systemd = {
    services = {
      tempo.serviceConfig = {
        MemoryMax = "512M";
        CPUQuota = "20%";
        Nice = 10;
        DynamicUser = lib.mkForce false;
      };

      # Boot trace
      soyo-boot-trace = {
        description = "Generate boot trace from systemd-analyze";
        after = [
          "multi-user.target"
          "tempo.service"
        ];
        wants = [ "tempo.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = hardening.networkClient // {
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
          TimeoutStartSec = "1m";
          Restart = "no";
        };
      };

      # Activation trace
      soyo-activation-trace = {
        description = "Trace nixos-rebuild activation";
        after = [
          "multi-user.target"
          "tempo.service"
        ];
        wants = [ "tempo.service" ];
        serviceConfig = hardening.networkClient // {
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
          TimeoutStartSec = "1m";
          Restart = "no";
        };
      };
      soyo-health-trace = {
        description = "Periodic health checks as traces";
        after = [
          "multi-user.target"
          "tempo.service"
        ];
        wants = [ "tempo.service" ];
        serviceConfig = hardening.networkClient // {
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
          TimeoutStartSec = "1m";
          Restart = "no";
        };
      };
    };
    paths.soyo-activation-trace = {
      description = "Watch for NixOS activation";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/run/current-system";
        Unit = "soyo-activation-trace.service";
      };
    };
    timers.soyo-health-trace = {
      description = "Periodic health check trace";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "10m";
        RandomizedDelaySec = "60";
        Persistent = true;
      };
    };
    tmpfiles.rules = [
      "d /persist/var/lib/tempo/generator-wal 0750 tempo tempo -"
      "d /persist/var/lib/tempo/generator-traces 0750 tempo tempo -"
    ];
  };
}
