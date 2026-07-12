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
  *) printf '%s\n' '. active enabled persistent custom-host test-host soyo workstation appliance node_ lan_device_ Permission denied Location success # HELP "health":"up" 0.0.0.0 10.0.0.9' ;;
esac
