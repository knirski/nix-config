#!/usr/bin/env bats
# Exercises the *actual* embedded shell logic that determines backup
# freshness (scripts/healthcheck.sh: freshness_probe_snippet /
# check_backup_freshness), with no SSH involved at all.
#
# healthcheck.bats only ever intercepts the whole remote command as an
# opaque string (see tests/scripts/fixtures/fake-ssh.bash), so it can prove
# check_backup_freshness's outer SSH-dispatch and check_val plumbing work,
# but it can never catch a bug in the embedded NEVER_RAN/STALE/FRESH
# branching or timestamp arithmetic itself -- that gap is exactly what let
# two different bugs slip past a fully-green fixture-only suite:
#   1. ExecMainExitTimestamp never populating for restic's real
#      multi-ExecStart + ExecStartPre unit shape (fixed by switching to
#      InactiveEnterTimestamp -- see the first addendum in
#      .superpowers/sdd/task-O3-report.md).
#   2. Result/ExecMainStatus/InactiveEnterTimestamp all being systemd's
#      *mutable* bookkeeping of the last completed activation --
#      `systemctl reset-failed <unit>` silently resets Result back to
#      "success" and ExecMainStatus back to "0" without re-running
#      anything and without touching InactiveEnterTimestamp's *meaning* of
#      "whether that transition was clean" -- so a genuinely failed unit
#      that had been reset-failed still reported FRESH. Fixed by dropping
#      systemd unit properties entirely: the probe now reads only the
#      mtime of an immutable success marker file, touched by the backup
#      unit itself (modules/nixos/backup.nix) as the *last* ExecStart
#      entry -- reached only once every prior command in the oneshot
#      sequence has already exited 0 -- via `sudo stat -c %Y <marker>`.
#
# This test extracts the real freshness_probe_snippet() function body (and
# the real BACKUP_MAX_AGE_HOURS threshold) from the actual script source
# and runs the produced snippet directly via `bash -c`, with `stat` and
# `sudo` stubbed (tests/scripts/fixtures/fake-stat.bash,
# tests/scripts/fixtures/fake-sudo.bash) and a real `date` computing ages
# from now. Deliberately no `systemctl` fake is installed anywhere on this
# file's PATH -- if the probe ever regressed to reading systemd unit
# properties again, there would be nothing to answer it, and the affected
# tests would fail loudly (command not found) instead of silently passing.

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$TEST_ROOT/bin"
  ln -s "$FAKE_STAT" "$TEST_ROOT/bin/stat"
  ln -s "$FAKE_SUDO" "$TEST_ROOT/bin/sudo"
  export PATH="$TEST_ROOT/bin:$ORIGINAL_PATH"

  # Pull in the real BACKUP_MAX_AGE_HOURS constant and freshness_probe_snippet
  # function verbatim from the script source -- not a reimplementation --
  # so a future edit to either is exercised by this test unchanged.
  eval "$(sed -n '/^BACKUP_MAX_AGE_HOURS=/p' "$HEALTHCHECK_SRC")"
  eval "$(sed -n '/^freshness_probe_snippet() {/,/^}/p' "$HEALTHCHECK_SRC")"
  [[ "$BACKUP_MAX_AGE_HOURS" -gt 0 ]]
  declare -f freshness_probe_snippet >/dev/null
}

hours_ago() {
  echo $(( $(date +%s) - "$1" * 3600 ))
}

# Runs the real embedded probe snippet for $1 (a marker path -- never
# actually read from disk, fake-stat.bash ignores its arguments) with the
# fake `stat` reporting mtime=$2 (empty simulates a missing marker file,
# i.e. `stat` failing exactly as it does on a real ENOENT). Each invocation
# carries its own env via `env`, rather than `export`, so no state is
# shared across -- or assumed to survive -- the per-test subshell boundary
# Bats itself imposes.
run_probe() {
  local marker="$1" mtime="$2"
  env FAKE_STAT_MTIME="$mtime" bash -c "$(freshness_probe_snippet "$marker")"
}

@test "fresh marker reports FRESH with the computed age" {
  run run_probe /var/lib/restic-backups-zbook/last-success "$(hours_ago 3)"
  [[ "$status" -eq 0 ]]
  [[ "$output" == FRESH:* ]]
}

@test "stale marker (touched too long ago) reports STALE, not FRESH" {
  run run_probe /var/lib/restic-backups-zbook/last-success "$(hours_ago $((BACKUP_MAX_AGE_HOURS + 10)))"
  [[ "$status" -eq 0 ]]
  [[ "$output" == STALE:* ]]
}

@test "a missing marker file reports NEVER_RAN, never FRESH" {
  run run_probe /var/lib/btrbk-zbook/last-success ''
  [[ "$status" -eq 0 ]]
  [[ "$output" == "NEVER_RAN" ]]
}

@test "a non-numeric stat result is treated as maximally stale, never a silent pass" {
  run run_probe /var/lib/restic-backups-zbook/last-success 'not-a-real-timestamp'
  [[ "$status" -eq 0 ]]
  [[ "$output" == STALE:* ]]
}

@test "regression: reset-failed scenario -- marker absence alone drives the result, no systemctl involved" {
  # Reproduces the Critical finding on commits 0d61ed2/10ced03, confirmed
  # live on this repo's own zbook host: restic-backups-zbook.service's only
  # run one boot genuinely failed (a real DNS resolution failure to its
  # sftp backend), yet `systemctl show ... -p
  # Result,ExecMainStatus,InactiveEnterTimestamp --value` reported
  # success/0/a timestamp matching that failed run -- because something
  # (an operator, an alerting tool, automation) had run `systemctl
  # reset-failed` on it, which silently resets Result/ExecMainStatus
  # without re-running anything or touching any marker. A
  # Result/ExecMainStatus-based probe would report FRESH here; this test
  # proves the fixed probe cannot, since it never asks systemd anything at
  # all -- there is no `systemctl` fake anywhere on this file's PATH, so a
  # regression back to querying it would fail with "command not found"
  # rather than silently reporting FRESH.
  run run_probe /var/lib/restic-backups-zbook/last-success ''
  [[ "$status" -eq 0 ]]
  [[ "$output" != FRESH:* ]]
  [[ "$output" == "NEVER_RAN" ]]
}
