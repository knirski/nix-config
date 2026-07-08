#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OLD_REV=061eb80

for f in $(git show $OLD_REV:secrets/rekeyed/zbook/ | awk '/-/{print $NF}'); do
  NAME="${f#*-}"
  echo "==> Recovering $NAME..."
  git show "$OLD_REV:secrets/rekeyed/zbook/$f" > "/tmp/recover-$NAME"
  nix run nixpkgs#rage -- -d -i /persist/etc/ssh/ssh_host_ed25519_key "/tmp/recover-$NAME" 2>/dev/null \
    | nix run nixpkgs#rage -- -e -R ~/.ssh/soyo_ed25519.pub -o "secrets/$NAME" - 2>&1 \
    || echo "FAILED: $f"
  rm -f "/tmp/recover-$NAME"
done
