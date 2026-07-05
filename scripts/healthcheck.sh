#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${1:-soyo}"
IP="${2:-10.0.0.9}"
PASS=0
FAIL=0

pass() { echo "  [PASS] $*"; ((PASS++)); }
fail() { echo "  [FAIL] $*"; ((FAIL++)); }
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

echo "=== Healthcheck: $HOST ==="
echo ""

echo "--- Network ---"
check "enp1s0 is UP" \
  ssh "krzysiek@$HOST" 'ip link show enp1s0 | grep -q "state UP"'
check_val "Hostname is soyo" "soyo" \
  ssh "krzysiek@$HOST" hostname
check_val "Root SSH blocked" "Permission denied" \
  ssh -o ConnectTimeout=5 root@"$HOST" hostname
check "Static IP reachable" ping -c 1 -W 3 "$IP"

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
  ssh "krzysiek@$HOST" 'sudo cat /var/lib/dnsmasq/dnsmasq.leases'

echo ""
echo "--- Services ---"
for svc in blocky dnsmasq prometheus loki alloy grafana; do
  check_val "$svc is active" "active" \
    ssh "krzysiek@$HOST" "systemctl is-active $svc"
done

echo ""
echo "--- Timers ---"
for tmr in nix-gc btrfs-scrub free-space-check; do
  check_val "$tmr timer exists" "1" \
    ssh "krzysiek@$HOST" "systemctl list-timers --all --no-legend '$tmr*' | wc -l"
done

echo ""
echo "--- Metrics ---"
check_val "node_exporter (port 9100)" "node_" \
  curl -sf "http://$HOST:9100/metrics"
check_val "dnsmasq_exporter (port 9153)" "# HELP" \
  curl -sf "http://$HOST:9153/metrics"
check_val "Prometheus API (port 9090)" "WAL" \
  curl -sf "http://$HOST:9090"
check_val "Grafana (port 3000)" "200\|302\|Location" \
  curl -sI "http://$HOST:3000"

check_val "LAN inventory metrics" "lan_device_" \
  curl -sf "http://$HOST:9100/metrics" | grep lan_device_

echo ""
echo "--- Secrets ---"
check_val "agenix secrets decrypted" "." \
  ssh "krzysiek@$HOST" 'sudo ls /run/agenix/ | grep -q ntfy-token'

echo ""
echo "--- System ---"
check_val "Journald bounded (500M)" "500.0M" \
  ssh "krzysiek@$HOST" 'journalctl --header | grep "System Max Use"'

check_val "Tailscale connected" "soyo" \
  ssh "krzysiek@$HOST" 'tailscale status | grep -q soyo'

echo ""
echo "--- Storage ---"
SMART_DISK="/dev/disk/by-id/ata-PELADN_512GB_20250522100164"
check_val "SMART tests scheduled" "Self-test" \
  ssh "krzysiek@$HOST" "sudo smartctl -a '$SMART_DISK' 2>/dev/null | grep -q 'Self-test'"

check_val "btrbk snapshots exist" "." \
  ssh "krzysiek@$HOST" 'sudo btrbk -c /etc/btrbk/soyo.conf list 2>/dev/null | head -5 | grep -q .'

echo ""
echo "--- Secure Boot ---"
check_val "Secure Boot enabled" "enabled" \
  ssh "krzysiek@$HOST" 'sudo sbctl status | grep -q "Secure Boot.*enabled"'
check_val "sbctl keys persisted" "." \
  ssh "krzysiek@$HOST" 'sudo ls /persist/var/lib/sbctl/keys 2>/dev/null | head -5 | grep -q .'

echo ""
echo "--- Observability ---"
check_val "blackbox ICMP probes healthy" "up" \
  bash -c "curl -sf 'http://$HOST:9090/api/v1/targets' | grep -q blackbox-icmp.*up"
check_val "blackbox HTTP probes healthy" "up" \
  bash -c "curl -sf 'http://$HOST:9090/api/v1/targets' | grep -q blackbox-http.*up"

echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
