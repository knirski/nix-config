set -euo pipefail
# Minimal stand-in for `systemctl show <unit> -p <Property> --value`, used
# only by tests/scripts/backup-freshness-probe.bats to exercise the real
# embedded freshness_probe_snippet() shell logic from scripts/healthcheck.sh
# without any SSH involved. Each queried property is controlled by its own
# env var so a single test can set exactly the properties it cares about.
prop=""
next_is_prop=0
for arg in "$@"; do
  if [[ "$next_is_prop" == 1 ]]; then
    prop="$arg"
    next_is_prop=0
  elif [[ "$arg" == "-p" ]]; then
    next_is_prop=1
  fi
done
case "$prop" in
  Result) printf '%s\n' "${FAKE_SYSTEMCTL_RESULT:-success}" ;;
  ExecMainStatus) printf '%s\n' "${FAKE_SYSTEMCTL_CODE:-0}" ;;
  InactiveEnterTimestamp) printf '%s\n' "${FAKE_SYSTEMCTL_TS:-}" ;;
  *) printf '\n' ;;
esac
