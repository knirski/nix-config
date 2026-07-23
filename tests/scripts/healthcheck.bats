#!/usr/bin/env bats
load test-helper

setup() { setup_contract_test; }

@test "help is local and successful" {
  run env -i HOME="$HOME" "$PACKAGED_HEALTHCHECK" --help
  assert_status 0
  assert_output_has 'Usage:'
  [[ ! -s "$OPERATOR_TEST_LOG" ]]
}

@test "invalid host role and interface are rejected before SSH" {
  run "$HEALTHCHECK" 'bad;host' appliance eth0
  assert_status 2
  assert_output_has 'Invalid host'
  run "$HEALTHCHECK" host invalid-role eth0
  assert_status 2
  assert_output_has 'Unknown role'
  run "$HEALTHCHECK" host workstation 'eth 0'
  assert_status 2
  assert_output_has 'Invalid network interface'
  [[ ! -s "$OPERATOR_TEST_LOG" ]]
}

@test "explicit arguments preserve one remote command argument and skip discovery" {
  run "$HEALTHCHECK" custom-host workstation eth-explicit
  assert_status 0
  assert_output_has 'custom-host (role=workstation, nic=eth-explicit)'
  assert_log_lacks 'cat /etc/nix-config/role'
  assert_log_lacks 'ip -json link'
  assert_log_has '<krzysiek@custom-host> <ip link show eth-explicit | grep -q'
}

@test "unreachable host fails once before discovery" {
  run env SSH_FAIL_PATTERN='krzysiek@offline true' SSH_FAIL_OUTPUT='timed out' SSH_FAIL_STATUS=255 \
    "$HEALTHCHECK" offline
  assert_status 1
  assert_output_has 'Cannot connect to offline via SSH'
  assert_output_lacks 'timed out'
  [[ "$(grep -c 'krzysiek@offline' "$OPERATOR_TEST_LOG")" -eq 1 ]]
}

@test "declarative marker wins and compatibility fallback remains bounded" {
  export SSH_ROLE_MARKER=workstation SSH_APPLIANCE_FALLBACK=1
  run "$HEALTHCHECK" test-host
  assert_status 0
  assert_output_has 'role=workstation, nic=wlan-test'
  assert_log_lacks 'grep -q "10.0.0.0/24"'

  : >"$OPERATOR_TEST_LOG"
  export SSH_ROLE_MARKER='' SSH_APPLIANCE_FALLBACK=1
  run "$HEALTHCHECK" test-host
  assert_status 0
  assert_output_has 'role=appliance, nic=wlan-test'
  assert_log_has 'grep -q "10.0.0.0/24"'
}

@test "role contracts select exact services and DNS probes" {
  run "$HEALTHCHECK" test-host workstation eth0
  assert_status 0
  assert_log_has '<systemctl is-active --quiet greetd>'
  assert_log_lacks '<systemctl is-active --quiet blocky>'
  assert_log_lacks 'dig'

  : >"$OPERATOR_TEST_LOG"
  run "$HEALTHCHECK" test-host appliance eth0
  assert_status 0
  assert_log_has '<systemctl is-active --quiet blocky>'
  assert_log_has '<systemctl is-active --quiet dnsmasq>'
  assert_log_has 'dig <+short> <example.com> <@test-host>'
}

@test "inactive service is a failure, never an active substring match" {
  run env SSH_FAIL_PATTERN='systemctl is-active --quiet greetd' SSH_FAIL_OUTPUT='inactive' \
    "$HEALTHCHECK" test-host workstation eth0
  assert_status 1
  assert_output_has 'greetd (DMS greeter) is active'
  assert_output_has '1 failed'
}

@test "remote timeout-like failure is counted and later checks continue" {
  export SSH_FAIL_PATTERN='ip link show eth0' SSH_FAIL_OUTPUT='connection timed out' SSH_FAIL_STATUS=255
  run "$HEALTHCHECK" test-host workstation eth0
  assert_status 1
  assert_output_has '1 failed'
  assert_log_has '<bootctl status | grep -i "Secure Boot"'
  assert_output_lacks 'connection timed out'
}

@test "both host roles check their own declared snapshot timers and freshness" {
  run "$HEALTHCHECK" test-host appliance eth0
  assert_status 0
  assert_log_has '<systemctl is-enabled btrbk-soyo.timer'
  assert_log_has '<systemctl is-enabled restic-backups-soyo.timer'
  assert_log_has 'stat -c %Y /var/lib/btrbk-soyo/last-success'
  assert_log_has 'stat -c %Y /var/lib/restic-backups-soyo/last-success'
  assert_log_lacks 'btrbk-zbook'
  assert_log_lacks 'restic-backups-zbook'
  assert_output_has '[PASS] btrbk-soyo backup is fresh'
  assert_output_has '[PASS] restic-backups-soyo backup is fresh'

  : >"$OPERATOR_TEST_LOG"
  run "$HEALTHCHECK" test-host workstation eth0
  assert_status 0
  assert_log_has '<systemctl is-enabled btrbk-zbook.timer'
  assert_log_has '<systemctl is-enabled restic-backups-zbook.timer'
  assert_log_has 'stat -c %Y /var/lib/btrbk-zbook/last-success'
  assert_log_has 'stat -c %Y /var/lib/restic-backups-zbook/last-success'
  assert_log_lacks 'btrbk-soyo'
  assert_log_lacks 'restic-backups-soyo'
  assert_output_has '[PASS] btrbk-zbook backup is fresh'
  assert_output_has '[PASS] restic-backups-zbook backup is fresh'
}

@test "a stale backup fails with a specific message, not a generic one" {
  export BACKUP_STATE_RESTIC_SOYO='STALE:96h'
  run "$HEALTHCHECK" test-host appliance eth0
  assert_status 1
  assert_output_has 'restic-backups-soyo backup is fresh (expected: FRESH, got: STALE:96h)'
  # btrbk on the same host is unaffected -- only the stale unit fails.
  assert_output_has '[PASS] btrbk-soyo backup is fresh'
}

@test "reset-failed cannot mask a failed backup: an absent marker fails regardless of what systemd's mutable Result would say" {
  # Reproduces the Critical review finding on commits 0d61ed2/10ced03: the
  # prior probe trusted systemctl's Result/ExecMainStatus, which
  # `systemctl reset-failed <unit>` silently resets to success/0 without
  # re-running anything or touching any marker. The fixed probe never asks
  # systemd anything -- fake-ssh here answers purely from the
  # marker-file-stat command text, so this failure mode cannot recur no
  # matter what Result would claim.
  export BACKUP_STATE_BTRBK_ZBOOK='NEVER_RAN'
  run "$HEALTHCHECK" test-host workstation eth0
  assert_status 1
  assert_output_has 'btrbk-zbook backup is fresh (expected: FRESH, got: NEVER_RAN)'
  assert_output_has '[PASS] restic-backups-zbook backup is fresh'
}

@test "a backup unit that has never completed a run fails, not 'FRESH'" {
  export BACKUP_STATE_RESTIC_ZBOOK='NEVER_RAN'
  run "$HEALTHCHECK" test-host workstation eth0
  assert_status 1
  assert_output_has 'restic-backups-zbook backup is fresh (expected: FRESH, got: NEVER_RAN)'
}

@test "all blackbox targets healthy passes both probe jobs" {
  run "$HEALTHCHECK" test-host appliance eth0
  assert_status 0
  assert_output_has '[PASS] blackbox ICMP probes healthy'
  assert_output_has '[PASS] blackbox HTTP probes healthy'
}

@test "an empty blackbox target list fails, never silently passes" {
  export BLACKBOX_ICMP_STATE='NO_TARGETS'
  run "$HEALTHCHECK" test-host appliance eth0
  assert_status 1
  assert_output_has 'blackbox ICMP probes healthy (expected: ALL_UP, got: NO_TARGETS)'
  assert_output_has '[PASS] blackbox HTTP probes healthy'
}

@test "a single failed blackbox target fails the whole job, not just the section" {
  export BLACKBOX_HTTP_STATE='DOWN:nas.home.arpa'
  run "$HEALTHCHECK" test-host appliance eth0
  assert_status 1
  assert_output_has 'blackbox HTTP probes healthy (expected: ALL_UP, got: DOWN:nas.home.arpa)'
  assert_output_has '[PASS] blackbox ICMP probes healthy'
}
