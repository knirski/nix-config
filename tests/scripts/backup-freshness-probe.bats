#!/usr/bin/env bats
# Exercises the *actual* embedded shell logic that determines backup
# freshness (scripts/healthcheck.sh: freshness_probe_snippet /
# check_backup_freshness), with no SSH and no fake-ssh involved at all.
#
# healthcheck.bats only ever intercepts the whole remote command as an
# opaque string (see tests/scripts/fixtures/fake-ssh.bash), so it can prove
# check_backup_freshness's outer SSH-dispatch and check_val plumbing work,
# but it can never catch a bug in the embedded NEVER_RAN/FAILED/STALE/FRESH
# branching, timestamp parsing, or threshold arithmetic itself -- that gap
# is exactly what let a wrong systemd property (ExecMainExitTimestamp, which
# stays empty for restic-backups-<host>.service's real multi-ExecStart +
# ExecStartPre shape) go undetected by a 24/24-passing suite.
#
# This test instead extracts the real freshness_probe_snippet() function
# body (and the real BACKUP_MAX_AGE_HOURS threshold) from the actual script
# source and runs the produced snippet directly via `bash -c`, with
# `systemctl` stubbed (tests/scripts/fixtures/fake-systemctl.bash) and a real
# `date` computing ages from now.

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$TEST_ROOT/bin"
  ln -s "$FAKE_SYSTEMCTL" "$TEST_ROOT/bin/systemctl"
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
  date -d "@$(($(date +%s) - "$1" * 3600))" '+%a %Y-%m-%d %H:%M:%S %Z'
}

# Runs the real embedded probe snippet for $1 (unit name) with the fake
# systemctl reporting Result=$2, ExecMainStatus=$3, InactiveEnterTimestamp=$4.
# Each invocation carries its own env via `env`, rather than `export`, so no
# state is shared across -- or assumed to survive -- the per-test subshell
# boundary Bats itself imposes.
run_probe() {
  local service="$1" result="$2" code="$3" ts="$4"
  env FAKE_SYSTEMCTL_RESULT="$result" FAKE_SYSTEMCTL_CODE="$code" FAKE_SYSTEMCTL_TS="$ts" \
    bash -c "$(freshness_probe_snippet "$service")"
}

@test "fresh success reports FRESH with the computed age" {
  run run_probe restic-backups-zbook.service success 0 "$(hours_ago 3)"
  [[ "$status" -eq 0 ]]
  [[ "$output" == FRESH:* ]]
}

@test "stale success (ran too long ago) reports STALE, not FRESH" {
  run run_probe restic-backups-zbook.service success 0 "$(hours_ago $((BACKUP_MAX_AGE_HOURS + 10)))"
  [[ "$status" -eq 0 ]]
  [[ "$output" == STALE:* ]]
}

@test "failed last run reports FAILED with result and exit code, never FRESH" {
  run run_probe restic-backups-zbook.service failed 1 "$(hours_ago 1)"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "FAILED:result=failed,exit=1" ]]
}

@test "never-ran (empty timestamp property) reports NEVER_RAN, never FRESH" {
  run run_probe btrbk-zbook.service success 0 ''
  [[ "$status" -eq 0 ]]
  [[ "$output" == "NEVER_RAN" ]]
}

@test "an 'n/a' timestamp property also reports NEVER_RAN" {
  run run_probe btrbk-zbook.service success 0 'n/a'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "NEVER_RAN" ]]
}

@test "a timestamp that fails to parse is treated as maximally stale, never FRESH" {
  run run_probe restic-backups-zbook.service success 0 'not-a-real-timestamp'
  [[ "$status" -eq 0 ]]
  [[ "$output" == STALE:* ]]
}
