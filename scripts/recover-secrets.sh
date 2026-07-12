#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: recover-secrets [OPTIONS]

Recover master-encrypted .age files from a historical host-rekeyed tree.

Options:
  --revision REV          Git revision containing the rekeyed files
                         (default: 061eb80)
  --host HOST             Source host name (default: zbook)
  --host-identity FILE    Identity that decrypts historical host files
                         (default: /persist/etc/ssh/ssh_host_ed25519_key)
  --master-identity FILE  Recipient identity for recovered master files
                         (default: /etc/agenix-rekey/master-identity)
  --repo DIR              nix-config checkout (default: current Git root)
  --dry-run               List validated recovery operations; change nothing
  --yes                   Confirm the real mutation non-interactively
  -h, --help              Show this help

The command never stages, commits, pushes, rekeys, deploys, or prints secret
contents. Review recovered encrypted files before running `agenix rekey`.
EOF
}

die() { printf 'recover-secrets: %s\n' "$*" >&2; exit 2; }
require_private_file() {
  local label=$1 file=$2 mode owner
  [[ -f "$file" && -r "$file" ]] || die "$label is not readable"
  mode=$(stat -c '%a' "$file")
  owner=$(stat -c '%u' "$file")
  [[ "$owner" == "$(id -u)" ]] || die "$label must be owned by the current user"
  (( (8#$mode & 077) == 0 )) || die "$label must not be accessible by group or others"
}

REVISION=061eb80
HOST=zbook
HOST_IDENTITY=/persist/etc/ssh/ssh_host_ed25519_key
MASTER_IDENTITY=/etc/agenix-rekey/master-identity
REPO=""
DRY_RUN=0
CONFIRMED=0
GIT_BIN=${RECOVER_SECRETS_GIT:-git}
RAGE_BIN=${RECOVER_SECRETS_RAGE:-rage}

while (($#)); do
  case "$1" in
    --revision) (($# >= 2)) || die "--revision requires a value"; REVISION=$2; shift 2 ;;
    --host) (($# >= 2)) || die "--host requires a value"; HOST=$2; shift 2 ;;
    --host-identity) (($# >= 2)) || die "--host-identity requires a value"; HOST_IDENTITY=$2; shift 2 ;;
    --master-identity) (($# >= 2)) || die "--master-identity requires a value"; MASTER_IDENTITY=$2; shift 2 ;;
    --repo) (($# >= 2)) || die "--repo requires a value"; REPO=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) CONFIRMED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$HOST" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid host name"
[[ "$REVISION" =~ ^[A-Za-z0-9._/-]+$ ]] || die "invalid revision"
if [[ -z "$REPO" ]]; then
  REPO=$("$GIT_BIN" rev-parse --show-toplevel 2>/dev/null) || die "run inside the repository or pass --repo"
fi
[[ -f "$REPO/flake.nix" && -d "$REPO/secrets" ]] || die "--repo is not a nix-config checkout"

tree="secrets/rekeyed/$HOST"
mapfile -t files < <("$GIT_BIN" -C "$REPO" ls-tree --name-only "$REVISION:$tree")
((${#files[@]} > 0)) || die "no historical rekeyed files found"

declare -a names=()
declare -A seen_names=()
for file in "${files[@]}"; do
  [[ "$file" != */* && "$file" == *-*.age ]] || die "unsafe historical file name: $file"
  name=${file#*-}
  [[ "$name" =~ ^[A-Za-z0-9._-]+\.age$ ]] || die "unsafe recovered secret name"
  [[ -z "${seen_names[$name]:-}" ]] || die "duplicate recovered secret name: $name"
  seen_names[$name]=1
  names+=("$name")
  printf 'Would recover %s -> secrets/%s\n' "$tree/$file" "$name"
done
if ((DRY_RUN)); then
  printf 'Dry run: no files changed\n'
  exit 0
fi

((CONFIRMED)) || die "refusing mutation without --yes (use --dry-run to preview)"
require_private_file "host identity" "$HOST_IDENTITY"
require_private_file "master identity" "$MASTER_IDENTITY"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/recover-secrets.XXXXXX")
success=0
cleanup() {
  status=$?
  for name in "${names[@]}"; do
    rm -f "$REPO/secrets/$name.new"
    if ((success == 0)); then
      if [[ -e "$tmpdir/previous-$name" ]]; then
        cp -p "$tmpdir/previous-$name" "$REPO/secrets/$name"
      else
        rm -f "$REPO/secrets/$name"
      fi
    fi
  done
  rm -rf "$tmpdir"
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Capture every previous destination before any cryptographic operation. If a
# pipeline fails early, cleanup can still restore byte-identical state.
for name in "${names[@]}"; do
  [[ ! -e "$REPO/secrets/$name" ]] || cp -p "$REPO/secrets/$name" "$tmpdir/previous-$name"
done

for index in "${!files[@]}"; do
  file=${files[$index]}
  name=${names[$index]}
  historical="$tmpdir/historical.age"
  output="$tmpdir/recovered-$name"
  "$GIT_BIN" -C "$REPO" show "$REVISION:$tree/$file" > "$historical"
  "$RAGE_BIN" -d -i "$HOST_IDENTITY" "$historical" \
    | "$RAGE_BIN" -e -i "$MASTER_IDENTITY" -o "$output" -
  : > "$historical"
done

for name in "${names[@]}"; do
  install -m 0600 "$tmpdir/recovered-$name" "$REPO/secrets/$name.new"
done
for name in "${names[@]}"; do
  mv -f "$REPO/secrets/$name.new" "$REPO/secrets/$name"
done
success=1

printf '%s\n' 'Recovery complete. Review encrypted files, then run agenix rekey.'
