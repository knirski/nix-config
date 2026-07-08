#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"

if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname>"
  echo "Deploys to the given host. Uses deploy-rs remotely or nixos-rebuild locally."
  exit 1
fi

cd "$(dirname "$0")/.."

# Detect if we're on the target host
LOCAL_HOSTNAME=$(hostname 2>/dev/null || echo "")
if [ "$LOCAL_HOSTNAME" = "$HOST" ]; then
  echo "==> Deploying locally (nixos-rebuild)..."
  exec sudo nixos-rebuild switch --flake ".#$HOST"
else
  echo "==> Deploying remotely (deploy-rs)..."
  exec nix develop '.#' -c deploy ".#$HOST"
fi
