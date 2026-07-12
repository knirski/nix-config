set -euo pipefail
{
  printf 'nix'
  printf ' <%s>' "$@"
  printf '\n'
} >>"$OPERATOR_TEST_LOG"
printf '%s\n' "${NIX_STUB_OUTPUT:-fixture nix invocation}"
if [[ "${NIX_STUB_MUTATE_REKEYED:-0}" == 1 ]]; then
  rm -f secrets/rekeyed/zbook/hash-example.age
  mkdir -p secrets/rekeyed/soyo secrets/rekeyed/zbook
  printf 'partial replacement\n' >secrets/rekeyed/zbook/hash-example.age
  printf 'partial new host output\n' >secrets/rekeyed/soyo/new-partial.age
  chmod 0644 secrets/rekeyed/zbook/hash-example.age
fi
exit "${NIX_STUB_STATUS:-0}"
