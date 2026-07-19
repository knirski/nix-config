# shellcheck shell=bats
#
# Tests for lib/shared-env.zsh — the zsh-only env-var broadcast helpers.
# Each test invokes zsh to source the library and run the command under test.

setup() {
  export SHARED_ENV_FILE="$BATS_TEST_TMPDIR/shared-env"
  export SHARED_ENV_ZSH="$BATS_TEST_DIRNAME/../../lib/shared-env.zsh"
}

# ---------------------------------------------------------------------------
# shared-env
# ---------------------------------------------------------------------------

@test "shared-env sets a simple variable" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env FOO bar
    source \$SHARED_ENV_FILE
    echo \$FOO
  "
  [ "$output" = "bar" ]
}

@test "shared-env sets a variable with spaces" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env NAME 'John Doe'
    source \$SHARED_ENV_FILE
    echo \$NAME
  "
  [ "$output" = "John Doe" ]
}

@test "shared-env sets a variable with special characters" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env TOKEN 'abc123!#?=@/'
    source \$SHARED_ENV_FILE
    echo \$TOKEN
  "
  [ "$output" = "abc123!#?=@/" ]
}

@test "shared-env updates an existing variable" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env FOO first
    shared-env FOO second
    source \$SHARED_ENV_FILE
    echo \$FOO
  "
  [ "$output" = "second" ]
}

@test "shared-env does not duplicate entries on re-set" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env FOO bar
    shared-env FOO bar
    grep -c '^export FOO=' \$SHARED_ENV_FILE
  "
  [ "$output" = "1" ]
}

@test "shared-env preserves other variables when updating" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env A alpha
    shared-env B beta
    shared-env A gamma
    source \$SHARED_ENV_FILE
    echo \$A \$B
  "
  [ "$output" = "gamma beta" ]
}

@test "shared-env creates parent directory" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env FOO bar
    [[ -f \$SHARED_ENV_FILE ]]
  "
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# shared-env-rm
# ---------------------------------------------------------------------------

@test "shared-env-rm removes a variable" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env FOO bar
    shared-env-rm FOO
    source \$SHARED_ENV_FILE 2>/dev/null || true
    echo \${FOO:-unset}
  "
  [ "$output" = "unset" ]
}

@test "shared-env-rm removes only the named variable" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env A alpha
    shared-env B beta
    shared-env-rm A
    source \$SHARED_ENV_FILE
    echo \$A --- \$B
  "
  [ "$output" = "--- beta" ]
}

@test "shared-env-rm is idempotent" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env-rm NONEXISTENT
  "
  [ "$status" -eq 0 ]
}

@test "shared-env-rm works when file is missing" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    rm -f \$SHARED_ENV_FILE
    shared-env-rm FOO
  "
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# File integrity
# ---------------------------------------------------------------------------

@test "shared store is a valid shell file after multiple operations" {
  run zsh -c "
    source $SHARED_ENV_ZSH
    shared-env EDITOR nvim
    shared-env PAGER less
    shared-env BROWSER firefox
    shared-env-rm PAGER
    shared-env EDITOR vim
    source $SHARED_ENV_ZSH
  "
  [ "$status" -eq 0 ]
}
