set -euo pipefail
# Minimal stand-in for `stat -c %Y <path>`, used only by
# tests/scripts/backup-freshness-probe.bats to exercise the real embedded
# freshness_probe_snippet() shell logic from scripts/healthcheck.sh without
# any SSH or a real marker file on disk. Controlled by FAKE_STAT_MTIME:
# empty/unset simulates a missing marker file -- `stat` failing exactly as
# it does on a real ENOENT -- so freshness_probe_snippet's `-z "$ts"` guard
# is exercised the same way it would be against a real absent file. Any
# other value is echoed back verbatim as the mtime, as if `stat -c %Y` had
# printed it. The requested path (the marker file itself, and every other
# argument) is intentionally ignored -- this fixture only ever needs to
# answer with the one value each test cares about.
if [[ -z "${FAKE_STAT_MTIME:-}" ]]; then
  echo "stat: cannot statx '$*': No such file or directory" >&2
  exit 1
fi
printf '%s\n' "$FAKE_STAT_MTIME"
