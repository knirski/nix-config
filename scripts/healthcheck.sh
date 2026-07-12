#!/usr/bin/env bash
# shellcheck disable=SC2029
# Automated health check for any host in this flake.
#
# Usage:
#   healthcheck.sh [host] [role] [nic]
#     host  — SSH destination (default: soyo)
#     role  — "appliance" (DNS/DHCP + observability) or "workstation"
#             (default: read from the host's declarative role marker)
#     nic   — primary network interface (default: auto-detected on the host)
#
# Per-host facts (NIC, timers, appliance vs workstation) are discovered from
# the live system instead of being hardcoded, so the same script checks both
# Soyo and zbook. Appliance-only checks (Blocky/dnsmasq/DHCP/LAN
# inventory) only run when role=appliance.
set -euo pipefail

HOST="soyo"
ROLE=""
NIC=""
SSH_BIN=${HEALTHCHECK_SSH:-ssh}
DIG_BIN=${HEALTHCHECK_DIG:-dig}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: healthcheck.sh [host] [role] [nic]"
      echo "  host  SSH destination (default: soyo)"
      echo "  role  appliance | workstation (default: auto-detect)"
      echo "  nic   primary interface (default: auto-detect)"
      exit 0
      ;;
    *)
      if [[ -z "${HOST_SET:-}" ]]; then HOST="$1"; HOST_SET=1;
      elif [[ -z "${ROLE_SET:-}" ]]; then ROLE="$1"; ROLE_SET=1;
      else NIC="$1"; fi
      ;;
  esac
  shift
done

[[ "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  echo "Invalid host '$HOST'" >&2
  exit 2
}
if [[ -n "$NIC" && ! "$NIC" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
  echo "Invalid network interface '$NIC'" >&2
  exit 2
fi

# --- Discover facts from the live host when not given ---
if [[ -z "$NIC" ]]; then
  # First non-loopback, non-tailscale interface that is up.
  NIC="$("$SSH_BIN" -o ConnectTimeout=10 -o LogLevel=QUIET "krzysiek@$HOST" \
    'ip -json link | jq -r ".[] | select(.ifname!=\"lo\" and (.ifname|startswith(\"tailscale\")|not) and (.operstate==\"UP\")) | .ifname" | head -1' 2>/dev/null || echo "enp1s0")"
fi
if [[ ! "$NIC" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
  echo "Invalid network interface '$NIC'" >&2
  exit 2
fi
if [[ -z "$ROLE" ]]; then
  ROLE="$("$SSH_BIN" -o ConnectTimeout=10 -o LogLevel=QUIET "krzysiek@$HOST" \
    'cat /etc/nix-config/role 2>/dev/null' 2>/dev/null || true)"

  # Compatibility fallback for hosts still running a generation from before
  # the declarative marker was introduced.
  if [[ -z "$ROLE" ]]; then
    if "$SSH_BIN" -o ConnectTimeout=10 -o LogLevel=QUIET "krzysiek@$HOST" \
      'tailscale status 2>/dev/null | grep -q "10.0.0.0/24"' 2>/dev/null; then
      ROLE="appliance"
    else
      ROLE="workstation"
    fi
  fi
fi

if [[ "$ROLE" != "appliance" && "$ROLE" != "workstation" ]]; then
  echo "Unknown role '$ROLE' (expected appliance or workstation)" >&2
  exit 2
fi

PASS=0
FAIL=0

SSH_OPTS=(-o ConnectTimeout=10 -o LogLevel=QUIET)

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
  if printf '%s\n' "$out" | grep -Fq -- "$expected"; then
    pass "$desc"
  else
    fail "$desc (expected: $expected, got: $out)"
  fi
}
check_active() {
  local service=$1
  check "$service is active" run_ssh "systemctl is-active --quiet $service"
}
check_nonempty() {
  local desc=$1 out
  shift
  if out=$("$@" 2>/dev/null) && [[ -n "$out" ]]; then
    pass "$desc"
  else
    fail "$desc (expected non-empty output)"
  fi
}

# shellcheck disable=SC2329
run_ssh()  { "$SSH_BIN" "${SSH_OPTS[@]}" "krzysiek@$HOST" "$@"; }
# shellcheck disable=SC2329
run_sudo() { "$SSH_BIN" "${SSH_OPTS[@]}" "krzysiek@$HOST" sudo "$@"; }

echo "=== Healthcheck: $HOST (role=$ROLE, nic=$NIC) ==="
echo ""

echo "--- Network ---"
check "$NIC is UP" \
  run_ssh "ip link show $NIC | grep -q 'state UP'"
check_val "Hostname is $HOST" "$HOST" \
  run_ssh hostname
check_val "Root SSH blocked" "Permission denied" \
  "$SSH_BIN" -o ConnectTimeout=5 root@"$HOST" hostname

echo ""
echo "--- Services ---"
if [[ "$ROLE" == "appliance" ]]; then
  for svc in blocky dnsmasq prometheus loki alloy grafana; do
    check_active "$svc"
  done
else
  check "greetd (DMS greeter) is active" \
    run_ssh "systemctl is-active --quiet greetd"
fi

echo ""
echo "--- Timers ---"
if [[ "$ROLE" == "appliance" ]]; then
  for tmr in nix-store-optimise "btrbk-soyo" fstrim; do
    check_val "$tmr timer enabled" "enabled" \
      run_ssh "systemctl is-enabled ${tmr}.timer 2>/dev/null"
  done
else
  for tmr in nix-store-optimise fstrim; do
    check_val "$tmr timer enabled" "enabled" \
      run_ssh "systemctl is-enabled ${tmr}.timer 2>/dev/null"
  done
fi

echo ""
echo "--- Secrets ---"
check_nonempty "agenix secrets decrypted" run_sudo ls /run/agenix/

echo ""
echo "--- System ---"
check_val "Journald persistent" "persistent" \
  run_ssh 'grep "^Storage=persistent" /etc/systemd/journald.conf'
check_val "Tailscale connected" "$HOST" \
  run_ssh 'tailscale status'

echo ""
echo "--- Storage ---"
check "SMART enabled (smartd running)" \
  run_ssh 'systemctl is-active --quiet smartd'

echo ""
echo "--- Secure Boot ---"
check_val "Secure Boot enabled" "enabled" \
  run_ssh 'bootctl status | grep -i "Secure Boot" | grep -o "enabled"'
check_nonempty "sbctl keys persisted" run_sudo ls /persist/var/lib/sbctl/keys

if [[ "$ROLE" == "appliance" ]]; then
  echo ""
  echo "--- Metrics (appliance) ---"
  check_val "node_exporter (port 9100)" "node_" \
    run_ssh 'curl -sf http://localhost:9100/metrics | grep node_ | head -1'

  echo ""
  echo "--- DNS / DHCP (appliance) ---"
  check_nonempty "Forward DNS resolves" \
    "$DIG_BIN" +short example.com @"$HOST"
  check_val "Ad blocking (doubleclick.net)" "0.0.0.0" \
    "$DIG_BIN" +short doubleclick.net @"$HOST"
  check_val "Local resolution (soyo.home.arpa)" "10.0.0.9" \
    "$DIG_BIN" +short soyo.home.arpa @"$HOST"
  check_val "Reverse DNS (10.0.0.9)" "soyo" \
    "$DIG_BIN" +short -x 10.0.0.9 @"$HOST"
  check "DHCP lease file exists" \
    run_sudo test -f /var/lib/dnsmasq/dnsmasq.leases

  echo ""
  echo "--- Observability (appliance) ---"
  check_val "dnsmasq_exporter (port 9153)" "# HELP" \
    run_ssh 'curl -sf http://localhost:9153/metrics'
  check_val "Prometheus API (port 9090)" "success" \
    run_ssh 'curl -sf http://localhost:9090/api/v1/status/buildinfo'
  check_val "Grafana (port 3000)" "Location" \
    run_ssh 'curl -sI http://localhost:3000'
  check_val "LAN inventory metrics" "lan_device_" \
    run_ssh 'curl -sf http://localhost:9100/metrics | grep lan_device_'
  check_val "blackbox ICMP probes healthy" "\"health\":\"up\"" \
    run_ssh 'curl -sf http://localhost:9090/api/v1/targets | grep blackbox-icmp | head -5'
  check_val "blackbox HTTP probes healthy" "\"health\":\"up\"" \
    run_ssh 'curl -sf http://localhost:9090/api/v1/targets | grep blackbox-http | head -5'
fi

echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================"
exit $FAIL
