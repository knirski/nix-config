set -euo pipefail
{
  printf 'ssh'
  printf ' <%s>' "$@"
  printf '\n'
} >>"$OPERATOR_TEST_LOG"
command_line="$*"
if [[ -n "${SSH_FAIL_PATTERN:-}" && "$command_line" == *"$SSH_FAIL_PATTERN"* ]]; then
  printf '%s\n' "${SSH_FAIL_OUTPUT:-fixture remote failure}" >&2
  exit "${SSH_FAIL_STATUS:-1}"
fi
case "$command_line" in
  *'ip -json link'*) printf '%s\n' "${SSH_NIC:-wlan-test}" ;;
  *'cat /etc/nix-config/role'*) printf '%s' "${SSH_ROLE_MARKER:-}" ;;
  *'tailscale status 2>/dev/null | grep -q "10.0.0.0/24"'*) [[ "${SSH_APPLIANCE_FALLBACK:-0}" == 1 ]] ;;
  # Backup freshness probes (scripts/healthcheck.sh: check_backup_freshness).
  # Matched on "systemctl show <unit>.service" (not ".timer") so this never
  # shadows the separate is-enabled timer checks below. Each unit has its own
  # override so tests can make exactly one host/backend stale or failed
  # without disturbing the others. Default: healthy and fresh.
  *'systemctl show btrbk-soyo.service'*) printf '%s\n' "${BACKUP_STATE_BTRBK_SOYO:-FRESH:5h}" ;;
  *'systemctl show restic-backups-soyo.service'*) printf '%s\n' "${BACKUP_STATE_RESTIC_SOYO:-FRESH:5h}" ;;
  *'systemctl show btrbk-zbook.service'*) printf '%s\n' "${BACKUP_STATE_BTRBK_ZBOOK:-FRESH:5h}" ;;
  *'systemctl show restic-backups-zbook.service'*) printf '%s\n' "${BACKUP_STATE_RESTIC_ZBOOK:-FRESH:5h}" ;;
  # Blackbox probe queries (scripts/healthcheck.sh: check_blackbox_job).
  # Matched on the Prometheus targets endpoint plus the job label so the two
  # jobs (icmp/http) can be steered independently. Default: every target up.
  *'/api/v1/targets'*'blackbox-icmp'*) printf '%s\n' "${BLACKBOX_ICMP_STATE:-ALL_UP}" ;;
  *'/api/v1/targets'*'blackbox-http'*) printf '%s\n' "${BLACKBOX_HTTP_STATE:-ALL_UP}" ;;
  *) printf '%s\n' '. active enabled persistent custom-host test-host soyo workstation appliance node_ lan_device_ Permission denied Location success # HELP "health":"up" 0.0.0.0 10.0.0.9' ;;
esac
