#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

nix develop '.#' -c bash <<'SCRIPT'
set -euo pipefail

echo "==> Rekeying agenix secrets..."
agenix rekey

echo "==> Building system closure..."
STORE_PATH=$(nix build .#nixosConfigurations.soyo.config.system.build.toplevel --no-link --print-out-paths 2>/dev/null)

echo "==> Copying closure to soyo..."
nix copy --to "ssh://krzysiek@10.0.0.9" "$STORE_PATH"

echo "==> Activating on soyo..."
ssh krzysiek@10.0.0.9 sudo bash -s <<ACTIVATE
set -euo pipefail
systemctl reset-failed nixos-rebuild-switch-to-configuration.service 2>/dev/null || true
nix-env -p /nix/var/nix/profiles/system --set "$STORE_PATH"
"$STORE_PATH/bin/switch-to-configuration" switch
ACTIVATE

echo "==> Done"
SCRIPT
