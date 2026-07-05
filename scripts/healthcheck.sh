#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="soyo"
PASS=0
FAIL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: healthcheck.sh [--host <hostname>]"
      echo "  Runs automated health checks against a NixOS host via SSH."
      echo "  Default host: soyo"
      exit 0
      ;;
    --host)
      HOST="$2"; shift
      ;;
    *)
      HOST="$1"
      ;;
  esac
  shift
done

SSH_OPTS="-o ConnectTimeout=10 -o LogLevel=QUIET"

pass() { echo "  [PASS] $*"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $*"; ((FAIL++)) || true; }
check() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}
check_val() {
  local desc="$1" expected="$2"; shift 2
  local out; out=$("$@" 2>&1) || true
  if echo "$out" | grep -q "$expected"; then
    pass "$desc"
  else
    fail "$desc (expected: $expected, got: $out)"
  fi
}

run_ssh()  { ssh $SSH_OPTS "krzysiek@$HOST" "$@"; }
run_sudo() { ssh $SSH_OPTS "krzysiek@$HOST" "sudo $@"; }

echo "=== Healthcheck: $HOST ==="
echo ""

echo "--- Network ---"
check "enp1s0 is UP" \
  run_ssh 'ip link show enp1s0 | grep -q "state UP"'
check_val "Hostname is soyo" "soyo" \
  run_ssh hostname
check_val "Root SSH blocked" "Permission denied" \
  ssh -o ConnectTimeout=5 root@"$HOST" hostname

echo ""
echo "--- DNS ---"
check_val "Forward DNS resolves" "." \
  dig +short example.com @"$HOST"
check_val "Ad blocking (doubleclick.net)" "0.0.0.0" \
  dig +short doubleclick.net @"$HOST"
check_val "Local resolution (soyo.home.arpa)" "10.0.0.9" \
  dig +short soyo.home.arpa @"$HOST"
check_val "Reverse DNS (10.0.0.9)" "soyo" \
  dig +short -x 10.0.0.9 @"$HOST"

echo ""
echo "--- DHCP ---"
check_val "DHCP lease file exists" "." \
  run_sudo cat /var/lib/dnsmasq/dnsmasq.leases

echo ""
echo "--- Services ---"
for svc in blocky dnsmasq prometheus loki alloy grafana; do
  check_val "$svc is active" "active" \
    run_ssh "systemctl is-active $svc"
done

echo ""
echo "--- Timers ---"
for tmr in nix-store-optimise btrbk-soyo fstrim; do
  check_val "$tmr timer enabled" "enabled" \
    run_ssh "systemctl is-enabled ${tmr}.timer 2>/dev/null"
done

echo ""
echo "--- Metrics ---"
check_val "node_exporter (port 9100)" "node_" \
  run_ssh 'curl -sf http://localhost:9100/metrics | grep node_ | head -1'
check_val "dnsmasq_exporter (port 9153)" "# HELP" \
  run_ssh 'curl -sf http://localhost:9153/metrics'
check_val "Prometheus API (port 9090)" "success" \
  run_ssh 'curl -sf http://localhost:9090/api/v1/status/buildinfo'
check_val "Grafana (port 3000)" "Location" \
  run_ssh 'curl -sI http://localhost:3000'
check_val "LAN inventory metrics" "lan_device_" \
  run_ssh 'curl -sf http://localhost:9100/metrics | grep lan_device_'

echo ""
echo "--- Secrets ---"
check_val "agenix secrets decrypted" "." \
  run_sudo ls /run/agenix/

echo ""
echo "--- System ---"
check_val "Journald persistent" "persistent" \
  run_ssh 'grep "^Storage=persistent" /etc/systemd/journald.conf'
check_val "Tailscale connected" "soyo" \
  run_ssh 'tailscale status'

echo ""
echo "--- Storage ---"
check_val "SMART enabled (smartd running)" "active" \
  run_ssh 'systemctl is-active smartd' 2>/dev/null

echo ""
echo "--- Secure Boot ---"
check_val "Secure Boot enabled" "enabled" \
  run_ssh 'bootctl status | grep -i "Secure Boot" | grep -o "enabled"'
check_val "sbctl keys persisted" "." \
  run_sudo ls /persist/var/lib/sbctl/keys

echo ""
echo "--- Observability ---"
check_val "blackbox ICMP probes healthy" "\"health\":\"up\"" \
  run_ssh 'curl -sf http://localhost:9090/api/v1/targets | grep blackbox-icmp | head -5'
check_val "blackbox HTTP probes healthy" "\"health\":\"up\"" \
  run_ssh 'curl -sf http://localhost:9090/api/v1/targets | grep blackbox-http | head -5'

echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================"
exit $FAIL
