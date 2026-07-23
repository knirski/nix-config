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
if [[ -n "$ROLE" && "$ROLE" != "appliance" && "$ROLE" != "workstation" ]]; then
  echo "Unknown role '$ROLE' (expected appliance or workstation)" >&2
  exit 2
fi

# Fail once, quickly, before optional discovery would multiply connection
# timeouts. This also gives operators one clear transport error.
if ! "$SSH_BIN" -o ConnectTimeout=5 -o LogLevel=QUIET "krzysiek@$HOST" true 2>/dev/null; then
  echo "Error: Cannot connect to $HOST via SSH" >&2
  exit 1
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

# Both restic (modules/nixos/backup.nix: timerConfig.OnCalendar default
# "daily", RandomizedDelaySec up to 1h) and btrbk (onCalendar = "daily") run
# once a day. 48h -- double the schedule period -- tolerates one missed or
# delayed run (host powered off overnight, randomized start delay, a slow
# check pass) without masking a backup that is genuinely stuck for more than
# a full extra day.
BACKUP_MAX_AGE_HOURS=48

# Builds the POSIX-shell probe snippet that determines backup freshness from
# an immutable success marker file, not from any systemd unit property. This
# is the literal logic executed on the remote host over SSH by
# check_backup_freshness below; it is also invoked directly -- via
# `bash -c`, with `stat`/`sudo` stubbed and a real `date`, no SSH involved at
# all -- by the SSH-free unit tests in
# tests/scripts/backup-freshness-probe.bats, to exercise the actual
# NEVER_RAN/STALE/FRESH branching and timestamp arithmetic.
#
# A prior version of this probe read systemd's `Result`, `ExecMainStatus`,
# and `InactiveEnterTimestamp` unit properties (itself a fix for an earlier
# bug -- ExecMainExitTimestamp never populates for
# restic-backups-<host>.service's real multi-ExecStart + ExecStartPre unit
# shape -- see the addendum in .superpowers/sdd/task-O3-report.md). A later
# review found all three of those properties are systemd's *mutable*
# bookkeeping of "the last completed activation": `systemctl reset-failed
# <unit>` -- runnable by an operator, an alerting/ack tool, or any
# automation with SSH access -- silently resets Result back to "success" and
# ExecMainStatus back to "0" without re-running anything and without
# touching what InactiveEnterTimestamp actually means (it records *when*
# the unit last went inactive, never *whether* that transition was clean).
# Reproduced live on this repo's own zbook host: restic-backups-zbook's only
# run one morning genuinely failed (a real DNS resolution failure to its
# sftp backend), yet `systemctl show restic-backups-zbook.service -p
# Result,ExecMainStatus,InactiveEnterTimestamp --value` reported
# success/0/a timestamp matching that failed run -- meaning the old
# Result/ExecMainStatus-based probe reported FRESH for a backup that had
# actually failed.
#
# This version instead reads the mtime of an immutable success marker file
# (modules/nixos/backup.nix: `touch <marker>` is the *last* ExecStart entry
# on both the restic and btrbk backup units, appended via `lib.mkAfter` so
# it only runs -- and only updates the marker -- once every prior command
# in the oneshot's ExecStart sequence has already exited 0). No systemd
# unit property is read at all, so `systemctl reset-failed` has nothing to
# lie about: the marker's mtime is either genuinely recent or it is not.
#
# Prints exactly one of:
#   NEVER_RAN    -- the marker file does not exist (no run has ever reached
#                   the genuine-success ExecStart entry)
#   STALE:<age>h -- the marker is older than BACKUP_MAX_AGE_HOURS
#   FRESH:<age>h -- the marker is within the threshold
# A marker mtime that fails to parse as a number is treated as age=0-epoch
# (i.e. maximally stale), never as a silent pass.
freshness_probe_snippet() {
  local marker="$1"
  # This $-reference is evaluated by the shell that runs the snippet (the
  # remote host over SSH in production, or the local `bash -c` in tests),
  # not expanded here. The marker's containing directory is
  # root/service-user-owned (systemd StateDirectory=), not world-readable,
  # hence `sudo` -- the same passwordless-sudo access already used by
  # run_sudo elsewhere in this script.
  # shellcheck disable=SC2016
  printf '%s' '
ts=$(sudo stat -c %Y '"$marker"' 2>/dev/null)
if [ -z "$ts" ]; then
  echo NEVER_RAN
else
  case "$ts" in
    *[!0-9]*) ts=0 ;;
  esac
  now=$(date +%s)
  age=$(( (now - ts) / 3600 ))
  if [ "$age" -gt '"$BACKUP_MAX_AGE_HOURS"' ]; then
    echo "STALE:${age}h"
  else
    echo "FRESH:${age}h"
  fi
fi
'
}

check_backup_freshness() {
  local desc="$1" marker="$2"
  check_val "$desc" "FRESH" run_ssh "$(freshness_probe_snippet "$marker")"
}

# Requires every active target in the given Prometheus job to report
# health "up", and explicitly fails (never silently passes) when the job has
# no active targets at all -- a "grep | head" over the raw JSON can pass on
# just one matching line even when other targets in the same job are down,
# or when the job returns no targets whatsoever.
check_blackbox_job() {
  local desc="$1" job="$2"
  check_val "$desc" "ALL_UP" run_ssh \
    "curl -sf --connect-timeout 5 http://localhost:9090/api/v1/targets | jq -r '(.data.activeTargets // []) | map(select(.labels.job==\"$job\")) | if length==0 then \"NO_TARGETS\" elif (map(select(.health!=\"up\")) | length) > 0 then (\"DOWN:\" + ([.[] | select(.health!=\"up\") | (.labels.instance // \"unknown\")] | join(\",\"))) else \"ALL_UP\" end'"
}

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
  for tmr in nix-store-optimise "btrbk-soyo" "restic-backups-soyo" fstrim; do
    check_val "$tmr timer enabled" "enabled" \
      run_ssh "systemctl is-enabled ${tmr}.timer 2>/dev/null"
  done
else
  for tmr in nix-store-optimise "btrbk-zbook" "restic-backups-zbook" fstrim; do
    check_val "$tmr timer enabled" "enabled" \
      run_ssh "systemctl is-enabled ${tmr}.timer 2>/dev/null"
  done
fi

echo ""
echo "--- Backup freshness ---"
# Timer-enabled only proves the schedule is armed, not that a backup has
# actually run and succeeded recently -- that's what these checks add.
# A successful timer here is NOT proof of restorability; the actual restore
# path is exercised only by the manual restic restore drill (see
# docs/backup-and-restore.md), never by this automated script.
if [[ "$ROLE" == "appliance" ]]; then
  check_backup_freshness "btrbk-soyo backup is fresh" "/var/lib/btrbk-soyo/last-success"
  check_backup_freshness "restic-backups-soyo backup is fresh" "/var/lib/restic-backups-soyo/last-success"
else
  check_backup_freshness "btrbk-zbook backup is fresh" "/var/lib/btrbk-zbook/last-success"
  check_backup_freshness "restic-backups-zbook backup is fresh" "/var/lib/restic-backups-zbook/last-success"
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
  check_blackbox_job "blackbox ICMP probes healthy" "blackbox-icmp"
  check_blackbox_job "blackbox HTTP probes healthy" "blackbox-http"
fi

echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================"
exit $FAIL
