#!/usr/bin/env bash
# Raw restic integrity and restore contract.  Every destructive mutation is
# confined to the build directory supplied by the Nix check.
set -euo pipefail

work=${1:?usage: restic-integration WORKDIR}
case "$work" in
  "$TMPDIR"/*) ;;
  *)
    printf 'refusing unsafe work directory: %s\n' "$work" >&2
    exit 64
    ;;
esac
mkdir -p "$work/home"
export HOME="$work/home"

source_tree="$work/source tree"
expected="$work/expected"
repository="$work/repository"
password_file="$work/password"
export RESTIC_PASSWORD_FILE="$password_file"

mkdir -p "$source_tree/nested directory"
printf 'fixture repository password\n' >"$password_file"
printf 'original payload\n' >"$source_tree/nested directory/payload.txt"
: >"$source_tree/empty file"
printf '#!/bin/sh\nprintf test-mode\n' >"$source_tree/executable"
chmod 0750 "$source_tree/executable"
ln -s 'nested directory/payload.txt' "$source_tree/payload link"
cp -a -- "$source_tree" "$expected"

restic init --repo "$repository"
restic backup --repo "$repository" "$source_tree"
cp -a -- "$repository" "$work/intact-repository"

# Checking encrypted pack contents and restoring them prove different things;
# the test deliberately requires both.
restic check --read-data --repo "$work/intact-repository"
# Mutate and then delete the source. A successful comparison below can only
# come from the snapshot, never from accidentally reusing live source data.
printf 'post-backup mutation\n' >"$source_tree/nested directory/payload.txt"
rm -rf -- "$source_tree"
mkdir -p "$work/restore"
restic restore --repo "$work/intact-repository" latest --target "$work/restore"
restored="$work/restore$source_tree"
diff --recursive --no-dereference -- "$expected" "$restored"
test "$(stat -c %a "$restored/executable")" = 750
test "$(readlink "$restored/payload link")" = 'nested directory/payload.txt'

# The comparison must detect data corruption independently of restic's check.
printf 'mutated restore\n' >"$restored/nested directory/payload.txt"
if diff --recursive --no-dereference -- "$expected" "$restored" >"$work/restore-mutation.log"; then
  printf 'mutated restored data unexpectedly compared equal\n' >&2
  exit 1
fi

printf 'wrong password\n' >"$work/wrong-password"
if RESTIC_PASSWORD_FILE="$work/wrong-password" restic snapshots --repo "$work/intact-repository" >"$work/wrong-password.log" 2>&1; then
  printf 'wrong password unexpectedly opened repository\n' >&2
  exit 1
fi
grep -Eiq 'password|decrypt|key' "$work/wrong-password.log"

if restic snapshots --repo "$work/missing-repository" >"$work/missing-repository.log" 2>&1; then
  printf 'missing repository unexpectedly opened\n' >&2
  exit 1
fi
grep -Eiq 'repository|config|does not exist' "$work/missing-repository.log"

mkdir "$work/read-only-parent"
chmod 0500 "$work/read-only-parent"
if restic init --repo "$work/read-only-parent/repository" >"$work/read-only.log" 2>&1; then
  printf 'read-only repository target unexpectedly initialized\n' >&2
  exit 1
fi
grep -Eiq 'permission|denied|repository' "$work/read-only.log"

# Corrupt only a copy. Truncating a data pack is deterministic and exercises
# authenticated-data verification rather than depending on a random bit flip.
cp -a -- "$work/intact-repository" "$work/corrupt-repository"
pack=$(find "$work/corrupt-repository/data" -type f -print -quit)
test -n "$pack"
size=$(stat -c %s "$pack")
test "$size" -gt 32
chmod u+w "$pack"
truncate -s "$((size - 17))" "$pack"
if restic check --read-data --repo "$work/corrupt-repository" >"$work/corruption.log" 2>&1; then
  printf 'corrupted repository unexpectedly passed read-data check\n' >&2
  exit 1
fi
grep -Eiq 'pack|blob|error|invalid|corrupt|truncated' "$work/corruption.log"

touch "$work/passed"
