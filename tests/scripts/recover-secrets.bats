#!/usr/bin/env bats
load test-helper

setup() { setup_contract_test; create_recovery_history; }

@test "help and validation use documented statuses without Git or rage mutation" {
  run env -i HOME="$HOME" "$PACKAGED_RECOVER_SECRETS" --help
  assert_status 0
  run "$RECOVER_SECRETS" --host ../escape --repo "$TEST_ROOT/repo" --dry-run
  assert_status 2
  assert_output_has 'invalid host name'
  [[ ! -s "$OPERATOR_TEST_LOG" ]]
}

@test "dry run handles paths with spaces and changes nothing" {
  mv "$TEST_ROOT/repo" "$TEST_ROOT/repo with spaces"
  run "$RECOVER_SECRETS" --repo "$TEST_ROOT/repo with spaces" --revision HEAD --host zbook --dry-run
  assert_status 0
  assert_output_has 'Dry run: no files changed'
  [[ ! -e "$TEST_ROOT/repo with spaces/secrets/example.age" ]]
  [[ ! -s "$OPERATOR_TEST_LOG" ]]
}

@test "successful recovery writes only encrypted mode-600 output and redacts plaintext" {
  run "$RECOVER_SECRETS" --repo "$TEST_ROOT/repo" --revision HEAD --host zbook \
    --host-identity "$TEST_ROOT/host-identity" --master-identity "$TEST_ROOT/master-identity" --yes
  assert_status 0
  assert_output_lacks 'FIXTURE-PLAINTEXT-MUST-NOT-LEAK'
  [[ "$(stat -c %a "$TEST_ROOT/repo/secrets/example.age")" == 600 ]]
  grep -Fq 'age-encryption.org/v1' "$TEST_ROOT/repo/secrets/example.age"
}

@test "encryption failure leaves an existing destination byte-identical and cleans temporaries" {
  printf 'previous ciphertext\n' >"$TEST_ROOT/repo/secrets/example.age"
  cp "$TEST_ROOT/repo/secrets/example.age" "$TEST_ROOT/before"
  export RAGE_FAIL_PATTERN='master-identity'
  run "$RECOVER_SECRETS" --repo "$TEST_ROOT/repo" --revision HEAD --host zbook \
    --host-identity "$TEST_ROOT/host-identity" --master-identity "$TEST_ROOT/master-identity" --yes
  [[ "$status" -ne 0 ]]
  cmp "$TEST_ROOT/before" "$TEST_ROOT/repo/secrets/example.age"
  [[ -z "$(find "$TEST_ROOT/repo/secrets" -name '*.new' -print -quit)" ]]
  assert_output_lacks 'FIXTURE-PLAINTEXT-MUST-NOT-LEAK'
}
