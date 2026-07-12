#!/usr/bin/env bats
load test-helper

setup() {
  setup_contract_test
  printf 'fixture-soyo-secret\n' >"$TEST_ROOT/soyo key"
  printf 'fixture-zbook-secret\n' >"$TEST_ROOT/zbook key"
  printf 'identity\n' >"$TEST_ROOT/master identity"
  chmod 0600 "$TEST_ROOT/soyo key" "$TEST_ROOT/zbook key" "$TEST_ROOT/master identity"
}

key_args() {
  printf '%s\n' --soyo-key-file "$TEST_ROOT/soyo key" --zbook-key-file "$TEST_ROOT/zbook key" \
    --master-identity "$TEST_ROOT/master identity" --repo "$TEST_ROOT/repo"
}

@test "help and unsafe secret argv reject without revealing the value" {
  run env -i HOME="$HOME" "$PACKAGED_SET_TAILSCALE_KEYS" --help
  assert_status 0
  run "$SET_TAILSCALE_KEYS" --soyo-key TOP-SECRET --zbook-key TOP-SECRET
  assert_status 2
  assert_output_has 'would expose a secret in argv'
  assert_output_lacks 'TOP-SECRET'
}

@test "dry run with spaced paths performs no writes or subprocesses" {
  mapfile -t args < <(key_args)
  run "$SET_TAILSCALE_KEYS" "${args[@]}" --dry-run
  assert_status 0
  assert_output_has 'Dry run: no files changed'
  assert_output_lacks 'fixture-soyo-secret'
  [[ ! -e "$TEST_ROOT/repo/secrets/tailscale-auth-key-soyo.age" ]]
  [[ ! -s "$OPERATOR_TEST_LOG" ]]
}

@test "over-permissive secret input is rejected before encryption" {
  chmod 0644 "$TEST_ROOT/soyo key"
  mapfile -t args < <(key_args)
  run "$SET_TAILSCALE_KEYS" "${args[@]}" --dry-run
  assert_status 2
  assert_output_has 'must not be accessible by group or others'
  [[ ! -s "$OPERATOR_TEST_LOG" ]]
}

@test "successful update passes exact Nix argv and never logs secrets" {
  mapfile -t args < <(key_args)
  run "$SET_TAILSCALE_KEYS" "${args[@]}" --yes
  assert_status 0
  assert_log_has 'nix <develop> <.#> <-c> <agenix> <rekey>'
  assert_output_lacks 'fixture-soyo-secret'
  assert_log_lacks 'fixture-soyo-secret'
  [[ "$(stat -c %a "$TEST_ROOT/repo/secrets/tailscale-auth-key-soyo.age")" == 600 ]]
}

@test "Nix failure rolls both destinations back and removes partial files" {
  printf 'old soyo\n' >"$TEST_ROOT/repo/secrets/tailscale-auth-key-soyo.age"
  printf 'old zbook\n' >"$TEST_ROOT/repo/secrets/tailscale-auth-key-zbook.age"
  mkdir -p "$TEST_ROOT/repo/secrets/rekeyed/zbook"
  printf 'old generated ciphertext\n' >"$TEST_ROOT/repo/secrets/rekeyed/zbook/hash-example.age"
  chmod 0600 "$TEST_ROOT/repo/secrets/rekeyed/zbook/hash-example.age"
  cp -a "$TEST_ROOT/repo/secrets" "$TEST_ROOT/before-secrets"
  export NIX_STUB_STATUS=42 NIX_STUB_OUTPUT='fixture rekey failure' NIX_STUB_MUTATE_REKEYED=1
  mapfile -t args < <(key_args)
  run "$SET_TAILSCALE_KEYS" "${args[@]}" --yes
  [[ "$status" -ne 0 ]]
  diff -r "$TEST_ROOT/before-secrets" "$TEST_ROOT/repo/secrets"
  [[ "$(stat -c %a "$TEST_ROOT/repo/secrets/rekeyed/zbook/hash-example.age")" == 600 ]]
  [[ ! -e "$TEST_ROOT/repo/secrets/rekeyed/soyo/new-partial.age" ]]
  [[ -z "$(find "$TEST_ROOT/repo/secrets" -name '*.new' -print -quit)" ]]
}
