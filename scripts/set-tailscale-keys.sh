#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --soyo-key <key> --zbook-key <key>"
  echo ""
  echo "Creates per-host Tailscale auth key secrets, rekeys, and commits."
  echo "Generate the keys at https://login.tailscale.com/admin/settings/keys"
  exit 1
}

SOYO_KEY=""
ZBOOK_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --soyo-key) SOYO_KEY="$2"; shift 2 ;;
    --zbook-key) ZBOOK_KEY="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -z "$SOYO_KEY" || -z "$ZBOOK_KEY" ]]; then
  usage
fi

cd "$(dirname "$0")/.."

RAGE="nix run nixpkgs#rage --"
MASTER_KEY=~/.ssh/soyo_ed25519

echo "==> Creating soyo tailscale auth key secret..."
echo -n "$SOYO_KEY" | $RAGE -e -R "$MASTER_KEY.pub" -o secrets/tailscale-auth-key-soyo.age -

echo "==> Creating zbook tailscale auth key secret..."
echo -n "$ZBOOK_KEY" | $RAGE -e -R "$MASTER_KEY.pub" -o secrets/tailscale-auth-key-zbook.age -

echo "==> Rekeying for all hosts..."
nix develop '.#' -c agenix rekey

echo "==> Staging files..."
git add secrets/tailscale-auth-key-soyo.age secrets/tailscale-auth-key-zbook.age secrets/rekeyed/

echo "==> Committing..."
git commit -m "chore: set tailscale auth keys per host"

echo "==> Done! Run:"
echo "    git push origin main"
echo "    deploy .#soyo"
echo "    sudo nixos-rebuild switch --flake .#zbook"
