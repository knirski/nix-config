set -euo pipefail
{
  printf 'rage'
  printf ' <%s>' "$@"
  printf '\n'
} >>"$OPERATOR_TEST_LOG"
if [[ " $* " == *' -d '* ]]; then
  printf '%s\n' 'FIXTURE-PLAINTEXT-MUST-NOT-LEAK'
  exit 0
fi
if [[ -n "${RAGE_FAIL_PATTERN:-}" && "$*" == *"$RAGE_FAIL_PATTERN"* ]]; then
  printf '%s\n' 'fixture encryption failure' >&2
  exit 23
fi
output=''
while (($#)); do
  if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi
done
[[ -n "$output" ]]
cat >/dev/null
printf '%s\n' 'age-encryption.org/v1 fixture ciphertext' >"$output"
