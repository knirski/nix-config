#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

nix develop '.#' -c bash <<'SCRIPT'
set -euo pipefail

echo "==> Rekeying agenix secrets..."
agenix rekey

echo "==> Deploying to soyo..."
deploy .#soyo

echo "==> Done"
SCRIPT
