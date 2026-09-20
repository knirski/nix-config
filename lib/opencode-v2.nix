# OpenCode v2 packages (CLI + desktop app). nixpkgs, even unstable, still
# ships v1.x, so both come from the upstream `opencode-v2` flake input. That
# input deliberately does not follow nixpkgs-unstable: its node_modules
# fixed-output hash is computed against the bun version pinned in its own
# flake.lock, and following ours would invalidate the hash (see flake.nix).
#
# The desktop derivation carries a local workaround for an upstream bug:
# `bun run build` runs packages/desktop/scripts/prebuild.ts, which in the
# prod channel requires `$OPENCODE_CLI_DIST/<cli-package>/package.json` next
# to the staged CLI binary (the manifest's version is what the binary prints
# for --version), but nix/desktop.nix only copies `bin/opencode`. Stage the
# manifest in preBuild — before buildPhase's own mkdir/cp — until upstream
# fixes its derivation.
{ opencodeV2 }:
{
  inherit (opencodeV2) opencode;

  opencode-desktop = opencodeV2.opencode-desktop.overrideAttrs (old: {
    preBuild = old.preBuild + ''
      export OPENCODE_CLI_DIST="$TMPDIR/desktop-cli"
      cli_package=$(cd packages/desktop && bun -e 'import { getCurrentCli } from "./scripts/utils.ts"; console.log(getCurrentCli().package.replace("@opencode/", ""))')
      mkdir -p "$OPENCODE_CLI_DIST/$cli_package"
      printf '{"version":"%s"}\n' "${opencodeV2.opencode.version}" > "$OPENCODE_CLI_DIST/$cli_package/package.json"
    '';
  });
}
