#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

nix develop '.#' -c bash <<'SCRIPT'
set -euo pipefail

echo "==> Rekeying agenix secrets..."
agenix rekey

echo "==> Deploying to zbook..."
nixos-rebuild switch --flake .#zbook --target-host "krzysiek@zbook" --sudo

echo "==> Done"
SCRIPT
