set -euo pipefail
# Minimal stand-in for `sudo`, used only by
# tests/scripts/backup-freshness-probe.bats so the real embedded
# freshness_probe_snippet() shell logic (scripts/healthcheck.sh) -- which
# invokes `sudo stat -c %Y <marker>` because the marker's parent directory
# is root/service-user-owned, not world-readable -- can run unprivileged
# inside the test sandbox. Simply execs its arguments directly; no
# privilege escalation is needed or attempted here.
exec "$@"
