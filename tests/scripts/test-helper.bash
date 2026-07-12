setup_contract_test() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/root"
  export HOME="$TEST_ROOT/home"
  export OPERATOR_TEST_LOG="$TEST_ROOT/commands.log"
  mkdir -p "$HOME" "$TEST_ROOT/repo/secrets" "$TEST_ROOT/bin"
  touch "$TEST_ROOT/repo/flake.nix" "$OPERATOR_TEST_LOG"
  ln -s "$FAKE_SSH" "$TEST_ROOT/bin/ssh"
  ln -s "$FAKE_DIG" "$TEST_ROOT/bin/dig"
  ln -s "$FAKE_RAGE" "$TEST_ROOT/bin/rage"
  ln -s "$FAKE_NIX" "$TEST_ROOT/bin/nix"
  export PATH="$TEST_ROOT/bin:$ORIGINAL_PATH"
  unset SSH_FAIL_PATTERN SSH_FAIL_OUTPUT SSH_FAIL_STATUS SSH_ROLE_MARKER SSH_APPLIANCE_FALLBACK RAGE_FAIL_PATTERN NIX_STUB_STATUS NIX_STUB_OUTPUT NIX_STUB_MUTATE_REKEYED
}

assert_status() {
  # `status` and `output` are populated by Bats' `run` helper.
  # shellcheck disable=SC2154
  [[ "$status" -eq "$1" ]] || { printf 'expected status %s, got %s\n%s\n' "$1" "$status" "$output" >&2; return 1; }
}

assert_output_has() { [[ "$output" == *"$1"* ]] || { printf 'missing output: %s\n%s\n' "$1" "$output" >&2; return 1; }; }
assert_output_lacks() { [[ "$output" != *"$1"* ]] || { printf 'secret/unexpected output: %s\n' "$1" >&2; return 1; }; }
assert_log_has() { grep -Fq -- "$1" "$OPERATOR_TEST_LOG"; }
assert_log_lacks() { ! grep -Fq -- "$1" "$OPERATOR_TEST_LOG"; }

create_recovery_history() {
  local repo="$TEST_ROOT/repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name fixture
  git -C "$repo" config user.email fixture@example.invalid
  mkdir -p "$repo/secrets/rekeyed/zbook"
  printf 'encrypted fixture\n' >"$repo/secrets/rekeyed/zbook/hash-example.age"
  git -C "$repo" add flake.nix secrets/rekeyed/zbook/hash-example.age
  git -C "$repo" commit -qm fixture
  printf 'identity\n' >"$TEST_ROOT/host-identity"
  printf 'identity\n' >"$TEST_ROOT/master-identity"
  chmod 0600 "$TEST_ROOT/host-identity" "$TEST_ROOT/master-identity"
}
