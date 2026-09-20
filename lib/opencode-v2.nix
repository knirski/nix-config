# OpenCode v2 packages (CLI + desktop app). nixpkgs, even unstable, still
# ships v1.x, so both come from the upstream `opencode-v2` flake input. That
# input deliberately does not follow nixpkgs-unstable: its node_modules
# fixed-output hash is computed against the bun version pinned in its own
# flake.lock, and following ours would invalidate the hash (see flake.nix).
#
# Channel alignment (why we rebuild the CLI with OPENCODE_CHANNEL=latest):
# upstream's nix/opencode.nix compiles the CLI with OPENCODE_CHANNEL=prod.
# The CLI names its service registration file by channel — latest/dev/beta/
# next all use `service.json`, prod uses `service-prod.json` (see
# packages/cli/src/services/service-config.ts) — but the desktop's
# @opencode/client always reads the unsuffixed `service.json` (see
# packages/client/src/promise/service.ts). With the prod-channel CLI the
# desktop never discovers the background service it spawns: main.log stalls at
# `v2 CLI background service starting { reason: 'missing' }` and the splash
# logo spins until Service.ensure's 120 s timeout.
#
# Official releases avoid this because they leave OPENCODE_CHANNEL unset, so
# the CLI is compiled with channel `latest`. The desktop maps `latest` to its
# prod identity everywhere (scripts/utils.ts resolveChannel, electron.vite
# .config.ts, electron-builder.config.ts), so rebuilding the CLI with the same
# channel keeps the desktop app id (`ai.opencode.desktop`) while making both
# the bundled sidecar and the installed CLI register `service.json`.
#
# The desktop derivation also carries a local workaround for an upstream bug:
# `bun run build` runs packages/desktop/scripts/prebuild.ts, which in the
# prod channel requires `$OPENCODE_CLI_DIST/<cli-package>/package.json` next
# to the staged CLI binary (the manifest's version is what the binary prints
# for --version), but nix/desktop.nix only copies `bin/opencode`. Stage the
# manifest in preBuild — before buildPhase's own mkdir/cp — until upstream
# fixes its derivation.
{ opencodeV2 }:
let
  opencode = opencodeV2.opencode.overrideAttrs (old: {
    env = old.env // {
      OPENCODE_CHANNEL = "latest";
    };
  });

  opencode-desktop =
    (opencodeV2.opencode-desktop.override { inherit opencode; }).overrideAttrs
      (old: {
        preBuild = old.preBuild + ''
          export OPENCODE_CLI_DIST="$TMPDIR/desktop-cli"
          cli_package=$(cd packages/desktop && bun -e 'import { getCurrentCli } from "./scripts/utils.ts"; console.log(getCurrentCli().package.replace("@opencode/", ""))')
          mkdir -p "$OPENCODE_CLI_DIST/$cli_package"
          printf '{"version":"%s"}\n' "${opencode.version}" > "$OPENCODE_CLI_DIST/$cli_package/package.json"
        '';
      });
in
{
  inherit opencode opencode-desktop;
}
