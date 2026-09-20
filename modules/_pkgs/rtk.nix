# Package: rtk — Rust Token Killer
#
# CLI proxy that filters/compresses common dev command output before it
# reaches an LLM context (git, grep, find, etc.), cutting token usage.
# Not in nixpkgs (checked 2026-08-13; upstream ships no flake), so this
# builds the crate straight from the GitHub tag via buildRustPackage.
#
# NOTE: OpenCode v2 plugin port (temporary — delete when upstream ships it)
#   OpenCode >= 2.0.x refuses to load the v1 OpenCode plugin that this rtk
#   version's `rtk init -g --opencode` generates, so a hand-migrated v2 plugin
#   lives outside this repo at ~/.config/opencode/plugins/rtk.ts (under
#   /persist). When bumping rtk to a release that installs a v2-native plugin,
#   delete that local file and regenerate it with `rtk init -g --opencode`.
#   Upstream v2 port: https://github.com/rtk-ai/rtk/pull/3899
#   Tracking issue:   https://github.com/rtk-ai/rtk/issues/3463
#
# Updating to a newer version:
#   1. Bump `version` and `hash` (get via: nix-prefetch-url --unpack
#      https://github.com/rtk-ai/rtk/archive/refs/tags/v<version>.tar.gz).
#   2. Remove `cargoHash` and set it to lib.fakeHash.
#   3. Run:  nix build .#rtk 2>&1 | grep "got:"
#   4. Copy the printed hash back into `cargoHash`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.45.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    tag = "v${version}";
    hash = "sha256-weAyHM0nWLrM8JRbbXIfjUsHtAep3DOFyTO+M3BZ/iU=";
  };

  cargoHash = "sha256-tgW6il/xLxt/xwhUBJ4MNVnk0JSZ7iFjJaEobj5+H4o=";

  # rusqlite's "bundled" feature compiles its own vendored sqlite3 in a
  # build script, so no external sqlite dependency is needed.

  # Upstream's unit tests assume a writable $HOME, an ambient git repo, and
  # (for the curl-filter tests) network access -- none of which exist in the
  # Nix build sandbox. 19 of 2578 tests fail there for exactly that reason;
  # the binary itself builds and runs fine.
  doCheck = false;

  meta = {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    mainProgram = "rtk";
  };
}
