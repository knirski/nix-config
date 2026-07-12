set -euo pipefail
{
  printf 'dig'
  printf ' <%s>' "$@"
  printf '\n'
} >>"$OPERATOR_TEST_LOG"
printf '%s\n' '. 0.0.0.0 10.0.0.9 soyo'
