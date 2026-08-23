#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: update-command-code-desktop [VERSION] [--repo DIR]

Deterministic update path for the command-code-desktop package. If VERSION
is omitted, fetches the latest release from GitHub automatically.

  1. Resolves the target version (latest or specified).
  2. Fetches the .deb from GitHub releases and computes the SRI hash.
  3. Prints the version and hash values to paste into command-code-desktop.nix.

It prints every value a human needs to paste into command-code-desktop.nix;
it does NOT edit that file itself, does not touch flake.lock, and does not
commit anything.

Options:
  --repo DIR   nix-config checkout (default: current Git root)
  -h, --help   Show this help
EOF
}

die() { printf 'update-command-code-desktop: %s\n' "$*" >&2; exit 2; }

GIT_BIN=${UPDATE_COMMAND_CODE_DESKTOP_GIT:-git}
NIX_BIN=${UPDATE_COMMAND_CODE_DESKTOP_NIX:-nix}
CURL_BIN=${UPDATE_COMMAND_CODE_DESKTOP_CURL:-curl}
JQ_BIN=${UPDATE_COMMAND_CODE_DESKTOP_JQ:-jq}

VERSION=""
REPO=""
while (($#)); do
  case "$1" in
    --repo) (($# >= 2)) || die "--repo requires a value"; REPO=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)
      [[ -z "$VERSION" ]] || die "VERSION given more than once"
      VERSION=$1
      shift
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO=$("$GIT_BIN" rev-parse --show-toplevel 2>/dev/null) || die "run inside the repository or pass --repo"
fi
[[ -f "$REPO/flake.nix" && -f "$REPO/modules/_pkgs/command-code-desktop.nix" ]] || die "--repo is not a nix-config checkout"

API_ROOT="https://api.github.com/repos/CommandCodeAI/desktop"

if [[ -n "$VERSION" ]]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like X.Y.Z"
  tag="v${VERSION}"
  printf 'Fetching release %s ...\n' "$tag" >&2
  release_json=$("$CURL_BIN" --fail --silent --show-error --location \
    -H "Accept: application/vnd.github+json" \
    "$API_ROOT/releases/tags/$tag")
else
  printf 'Fetching latest release ...\n' >&2
  release_json=$("$CURL_BIN" --fail --silent --show-error --location \
    -H "Accept: application/vnd.github+json" \
    "$API_ROOT/releases/latest")
  VERSION=$(printf '%s' "$release_json" | "$JQ_BIN" -r '.tag_name' | sed 's/^v//')
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "could not determine latest version"
fi

asset_name="CommandCode-${VERSION}-amd64.deb"
# shellcheck disable=SC2016
asset_url=$(printf '%s' "$release_json" | "$JQ_BIN" -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url')
[[ -n "$asset_url" && "$asset_url" != "null" ]] || die "could not find $asset_name in release $VERSION"

printf 'Downloading %s ...\n' "$asset_url" >&2
prefetch_json=$("$NIX_BIN" store prefetch-file --json --hash-type sha256 "$asset_url")
src_hash=$(printf '%s' "$prefetch_json" | "$JQ_BIN" -r .hash)
[[ -n "$src_hash" ]] || die "could not determine hash"

cat <<SUMMARY

command-code-desktop update summary for version ${VERSION}
  url:  ${asset_url}
  hash: ${src_hash}

This script did NOT edit modules/_pkgs/command-code-desktop.nix. Paste the
values above into its version/hash fields, then:
  1. nix build path:.#checks.x86_64-linux.macbook-desktop-invariants (or just rebuild)
  2. Commit modules/_pkgs/command-code-desktop.nix.
SUMMARY
