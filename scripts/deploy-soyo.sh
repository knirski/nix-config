#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

nix develop '.#' -c bash <<'SCRIPT'
set -euo pipefail

echo "==> Rekeying agenix secrets..."
agenix rekey

echo "==> Deploying to soyo (local build, remote activation)..."
# Disable SSH ControlMaster to avoid hangs when nix-daemon restarts
# during activation and kills the persistent SSH connection.
export NIX_SSHOPTS="-o ControlMaster=no"
nixos-rebuild switch \
  --flake .#soyo \
  --target-host "krzysiek@10.0.0.9" \
  --sudo
SCRIPT
