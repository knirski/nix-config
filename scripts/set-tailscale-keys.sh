#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: set-tailscale-keys --soyo-key-file FILE --zbook-key-file FILE [OPTIONS]

Encrypt per-host Tailscale auth keys and run `agenix rekey`. Secret values are
read from protected files, never command-line arguments.

Options:
  --soyo-key-file FILE    File containing the Soyo auth key
  --zbook-key-file FILE   File containing the zbook auth key
  --master-identity FILE  Operator age identity (default below)
  --repo DIR              nix-config checkout (default: current Git root)
  --dry-run               Validate and show destinations; change nothing
  --yes                   Confirm the real mutation non-interactively
  -h, --help              Show this help

Default master identity: /etc/agenix-rekey/master-identity

After success, review and commit the encrypted master and generated rekeyed
files yourself. This command never stages, commits, pushes, or deploys.
EOF
}

die() { printf 'set-tailscale-keys: %s\n' "$*" >&2; exit 2; }
require_private_file() {
  local label=$1 file=$2 mode owner
  [[ -f "$file" && -r "$file" ]] || die "$label is not readable"
  mode=$(stat -c '%a' "$file")
  owner=$(stat -c '%u' "$file")
  [[ "$owner" == "$(id -u)" ]] || die "$label must be owned by the current user"
  (( (8#$mode & 077) == 0 )) || die "$label must not be accessible by group or others"
}

SOYO_KEY_FILE=""
ZBOOK_KEY_FILE=""
MASTER_IDENTITY=/etc/agenix-rekey/master-identity
REPO=""
DRY_RUN=0
CONFIRMED=0
GIT_BIN=${SET_TAILSCALE_KEYS_GIT:-git}
NIX_BIN=${SET_TAILSCALE_KEYS_NIX:-nix}
RAGE_BIN=${SET_TAILSCALE_KEYS_RAGE:-rage}

while (($#)); do
  case "$1" in
    --soyo-key-file) (($# >= 2)) || die "--soyo-key-file requires a value"; SOYO_KEY_FILE=$2; shift 2 ;;
    --zbook-key-file) (($# >= 2)) || die "--zbook-key-file requires a value"; ZBOOK_KEY_FILE=$2; shift 2 ;;
    --master-identity) (($# >= 2)) || die "--master-identity requires a value"; MASTER_IDENTITY=$2; shift 2 ;;
    --repo) (($# >= 2)) || die "--repo requires a value"; REPO=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) CONFIRMED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --soyo-key|--zbook-key) die "$1 would expose a secret in argv; use the corresponding --*-key-file option" ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$SOYO_KEY_FILE" && -n "$ZBOOK_KEY_FILE" ]] || die "both key files are required"
require_private_file "Soyo key file" "$SOYO_KEY_FILE"
require_private_file "zbook key file" "$ZBOOK_KEY_FILE"
[[ -s "$SOYO_KEY_FILE" && -s "$ZBOOK_KEY_FILE" ]] || die "key files must not be empty"

if [[ -z "$REPO" ]]; then
  REPO=$("$GIT_BIN" rev-parse --show-toplevel 2>/dev/null) || die "run inside the repository or pass --repo"
fi
[[ -f "$REPO/flake.nix" && -d "$REPO/secrets" ]] || die "--repo is not a nix-config checkout"

dest_soyo="$REPO/secrets/tailscale-auth-key-soyo.age"
dest_zbook="$REPO/secrets/tailscale-auth-key-zbook.age"
printf 'Would update encrypted files:\n  %s\n  %s\n' "$dest_soyo" "$dest_zbook"
printf 'Would run: nix develop .# -c agenix rekey\n'
if ((DRY_RUN)); then
  printf 'Dry run: no files changed\n'
  exit 0
fi

((CONFIRMED)) || die "refusing mutation without --yes (use --dry-run to preview)"
require_private_file "master identity" "$MASTER_IDENTITY"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/set-tailscale-keys.XXXXXX")
success=0
rekeyed="$REPO/secrets/rekeyed"
[[ ! -e "$dest_soyo" ]] || cp -p "$dest_soyo" "$tmpdir/soyo.previous"
[[ ! -e "$dest_zbook" ]] || cp -p "$dest_zbook" "$tmpdir/zbook.previous"
[[ ! -e "$rekeyed" ]] || cp -a "$rekeyed" "$tmpdir/rekeyed.previous"
cleanup() {
  status=$?
  rm -f "$dest_soyo.new" "$dest_zbook.new"
  if ((success == 0)); then
    if [[ -e "$tmpdir/soyo.previous" ]]; then cp -p "$tmpdir/soyo.previous" "$dest_soyo"; else rm -f "$dest_soyo"; fi
    if [[ -e "$tmpdir/zbook.previous" ]]; then cp -p "$tmpdir/zbook.previous" "$dest_zbook"; else rm -f "$dest_zbook"; fi
    # `agenix rekey` owns this generated tree, but it can update several host
    # files before returning failure. Restore its complete pre-run snapshot so
    # master and generated ciphertext remain one atomic operator transaction.
    rm -rf "$rekeyed"
    if [[ -e "$tmpdir/rekeyed.previous" ]]; then cp -a "$tmpdir/rekeyed.previous" "$rekeyed"; fi
  fi
  rm -rf "$tmpdir"
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

"$RAGE_BIN" -e -i "$MASTER_IDENTITY" -o "$tmpdir/soyo.age" "$SOYO_KEY_FILE"
"$RAGE_BIN" -e -i "$MASTER_IDENTITY" -o "$tmpdir/zbook.age" "$ZBOOK_KEY_FILE"
install -m 0600 "$tmpdir/soyo.age" "$dest_soyo.new"
install -m 0600 "$tmpdir/zbook.age" "$dest_zbook.new"
mv -f "$dest_soyo.new" "$dest_soyo"
mv -f "$dest_zbook.new" "$dest_zbook"

(cd "$REPO" && "$NIX_BIN" develop '.#' -c agenix rekey)
success=1
printf '%s\n' 'Encrypted and rekeyed successfully. Review git diff before committing.'
