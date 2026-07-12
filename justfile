# Task runner for the nix-config flake.
# Run `just` to list recipes; `just <recipe>` to run one.

# List every recipe with its doc comment.
default:
    @just --list

# Format all Nix/Python/shell/markdown with treefmt.
fmt:
    nix run .#formatter

# Check formatting + static analysis (deadnix, statix, typos, shellcheck, ...).
lint:
    nix run .#formatter -- --check
    nix run .#deadnix -- .
    nix run nixpkgs#statix -- check .
    nix run nixpkgs#typos -- .
    nix run nixpkgs#actionlint -- .github/workflows/*.yml
    nix run nixpkgs#shellcheck -- scripts/healthcheck.sh

# Evaluate the whole flake (lints + builds every output incl. deploy checks).
check:
    nix flake check

# Build a host's toplevel system.
build host="soyo":
    nix build .#nixosConfigurations.{{host}}.config.system.build.toplevel

# Deploy to a host. Uses deploy-rs for remote hosts, nixos-rebuild for local.
deploy host="soyo":
    @CURRENT="$(hostname -s)" && \
    if [ "{{host}}" = "$CURRENT" ]; then \
      sudo nixos-rebuild switch --flake .#{{host}}; \
    else \
      nix develop '.#' -c deploy .#{{host}}; \
    fi

# Run the on-host health check over SSH.
#   just healthcheck            # soyo, role/nic auto-detected
#   just healthcheck zbook    # explicit host
healthcheck host="soyo" role="" nic="":
    nix run .#healthcheck -- {{host}} {{role}} {{nic}}

# Recover historical encrypted secrets. Pass --dry-run first; never auto-commits.
recover-secrets *args:
    nix run .#recover-secrets -- {{args}}

# Replace Tailscale key secrets from protected files; never auto-commits.
set-tailscale-keys *args:
    nix run .#set-tailscale-keys -- {{args}}

# Run dendritic option-namespace tests (wired into nix flake check, also runs there).
test:
    nix build .#checks.x86_64-linux.dendritic-options --no-link --print-out-paths

# Re-key all agenix secrets for every host after a key change.
rekey:
    nix run github:oddlama/agenix-rekey -- rekey

# Refresh the sanitized, public topology overview.
topology:
    topology=$(nix build path:.#topology-public-overview --no-link --print-out-paths); cp -f "$topology/overview.svg" docs/topology/overview.svg

# Build detailed operator diagrams locally and print their store path.
topology-operator-detailed:
    nix build path:.#topology-operator-detailed --no-link --print-out-paths

# Enter the dev shell with all tooling (pre-commit hooks auto-install).
dev:
    nix develop
