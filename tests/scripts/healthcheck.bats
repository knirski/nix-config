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
