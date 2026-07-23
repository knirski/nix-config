#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: update-command-code VERSION [--repo DIR]

Deterministic update path for the vendored command-code npm dependency
tree. Given a target upstream version, this:

  1. Fetches https://registry.npmjs.org/command-code/-/command-code-VERSION.tgz
     via `nix store prefetch-file` and prints the `fetchurl` hash.
  2. Regenerates modules/_pkgs/command-code-lock/package-lock.json in place,
     seeded from the currently-vendored lockfile (so already-resolved
     versions are preserved unless the new package.json's ranges force a
     change -- this is what makes a same-version re-run reproduce
     byte-identical output). Strips devDependencies and reapplies the
     OpenTelemetry CVE-2026-54285 override from command-code-lock/
     opentelemetry-overrides.json (edit that JSON file to add or retire an
     override; this script does not hardcode the override list).
  3. Runs the same fakeHash-then-build-then-extract dance documented in
     command-code.nix's header, against a throwaway copy of that file, and
     prints the resulting npmDepsHash.

It prints every value a human needs to paste into command-code.nix; it does
NOT edit that file's version/hash/npmDepsHash fields itself, does not touch
flake.lock, and does not commit anything. Review the regenerated lockfile
with `git diff` before committing.

Options:
  --repo DIR   nix-config checkout (default: current Git root)
  -h, --help   Show this help
EOF
}

die() { printf 'update-command-code: %s\n' "$*" >&2; exit 2; }

GIT_BIN=${UPDATE_COMMAND_CODE_GIT:-git}
NIX_BIN=${UPDATE_COMMAND_CODE_NIX:-nix}
NPM_BIN=${UPDATE_COMMAND_CODE_NPM:-npm}

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

[[ -n "$VERSION" ]] || { usage >&2; die "VERSION is required"; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like X.Y.Z"

if [[ -z "$REPO" ]]; then
  REPO=$("$GIT_BIN" rev-parse --show-toplevel 2>/dev/null) || die "run inside the repository or pass --repo"
fi
[[ -f "$REPO/flake.nix" && -f "$REPO/modules/_pkgs/command-code.nix" ]] || die "--repo is not a nix-config checkout"

PKG_DIR="$REPO/modules/_pkgs"
LOCK_DIR="$PKG_DIR/command-code-lock"
LOCKFILE="$LOCK_DIR/package-lock.json"
OVERRIDES_JSON="$LOCK_DIR/opentelemetry-overrides.json"
[[ -f "$LOCKFILE" ]] || die "missing $LOCKFILE"
[[ -f "$OVERRIDES_JSON" ]] || die "missing $OVERRIDES_JSON"

tmpdir=$("${UPDATE_COMMAND_CODE_MKTEMP:-mktemp}" -d "${TMPDIR:-/tmp}/update-command-code.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT

url="https://registry.npmjs.org/command-code/-/command-code-${VERSION}.tgz"
printf 'Fetching %s ...\n' "$url" >&2
prefetch_json=$("$NIX_BIN" store prefetch-file --json --hash-type sha512 "$url")
src_hash=$(printf '%s' "$prefetch_json" | "${UPDATE_COMMAND_CODE_JQ:-jq}" -r .hash)
tarball=$(printf '%s' "$prefetch_json" | "${UPDATE_COMMAND_CODE_JQ:-jq}" -r .storePath)
[[ -n "$src_hash" && -n "$tarball" ]] || die "could not determine fetchurl hash/store path"

# --- Regenerate the vendored lockfile -------------------------------------
extract_dir="$tmpdir/extract"
mkdir -p "$extract_dir"
tar xzf "$tarball" -C "$extract_dir"
pkg_dir="$extract_dir/package"
[[ -f "$pkg_dir/package.json" ]] || die "tarball did not contain package/package.json"

# Seed with the currently-vendored lockfile so npm preserves already-pinned
# resolutions (only touching what the new package.json's ranges actually
# force) rather than re-resolving the whole tree against today's registry
# state. This is what makes a same-version re-run idempotent.
cp "$LOCKFILE" "$pkg_dir/package-lock.json"
sed -i '/^  "devDependencies": {/,/^  }/d' "$pkg_dir/package.json"

sed_args=()
while IFS=$'\t' read -r override_package override_range; do
  sed_args+=( -e "s|\"${override_package}\": \"[^\"]*\"|\"${override_package}\": \"${override_range}\"|" )
done < <("${UPDATE_COMMAND_CODE_JQ:-jq}" -r '.overrides[] | "\(.package)\t\(.range)"' "$OVERRIDES_JSON")
((${#sed_args[@]} > 0)) || die "opentelemetry-overrides.json has no overrides entries"
sed -i "${sed_args[@]}" "$pkg_dir/package.json"

(cd "$pkg_dir" && "$NPM_BIN" install --package-lock-only --ignore-scripts >&2)
cp "$pkg_dir/package-lock.json" "$LOCKFILE"
printf 'Regenerated %s in place.\n' "$LOCKFILE" >&2

# --- Probe the real npmDepsHash via the documented fakeHash dance ---------
probe_dir="$tmpdir/probe"
mkdir -p "$probe_dir/command-code-lock"
cp "$PKG_DIR/command-code.nix" "$probe_dir/command-code.nix"
cp "$LOCKFILE" "$probe_dir/command-code-lock/package-lock.json"
cp "$OVERRIDES_JSON" "$probe_dir/command-code-lock/opentelemetry-overrides.json"
sed -i "s|version = \"[^\"]*\";|version = \"${VERSION}\";|" "$probe_dir/command-code.nix"
# The hash contains '/' (base64), so '|' is used as the sed delimiter here.
sed -i "s|hash = \"sha512-[^\"]*\";|hash = \"${src_hash}\";|" "$probe_dir/command-code.nix"
sed -i 's|npmDepsHash = "sha256-[^"]*";|npmDepsHash = lib.fakeHash;|' "$probe_dir/command-code.nix"

build_log="$tmpdir/probe-build.log"
printf 'Probing npmDepsHash (expected to fail with a hash mismatch) ...\n' >&2
"$NIX_BIN" build --impure --no-link --print-out-paths --expr \
  "let flake = builtins.getFlake \"${REPO}\"; pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; config.allowUnfree = true; }; in pkgs.callPackage ${probe_dir}/command-code.nix { }" \
  >"$build_log" 2>&1 || true

npm_deps_hash=$(grep -oE 'got: *sha256-[A-Za-z0-9+/=]+' "$build_log" | tail -1 | sed 's/got: *//') || true
if [[ -z "$npm_deps_hash" ]]; then
  cat "$build_log" >&2
  die "could not extract npmDepsHash from probe build output (see log above)"
fi

cat <<SUMMARY

command-code update summary for version ${VERSION}
  url:         ${url}
  hash:        ${src_hash}
  npmDepsHash: ${npm_deps_hash}
  lockfile:    ${LOCKFILE} (regenerated in place -- review with 'git diff')

This script did NOT edit modules/_pkgs/command-code.nix. Paste the values
above into its version/hash/npmDepsHash fields, then:
  1. nix build path:.#command-code
  2. nix build path:.#checks.x86_64-linux.command-code-security
  3. Review 'git diff -- modules/_pkgs/command-code-lock/package-lock.json'
     and update modules/_pkgs/command-code-lock/last-reviewed.json's date.
  4. Commit modules/_pkgs/command-code.nix and command-code-lock/ together.
SUMMARY
