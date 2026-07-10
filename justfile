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

# Run dendritic option-namespace tests (wired into nix flake check, also runs there).
test:
    nix build .#checks.x86_64-linux.dendritic-options --no-link --print-out-paths

# Re-key all agenix secrets for every host after a key change.
rekey:
    nix run github:oddlama/agenix-rekey -- rekey

# Render the LAN topology diagram to docs/topology/.
topology:
    nix build .#topology
    cp -f result/*.svg docs/topology/

# Enter the dev shell with all tooling (pre-commit hooks auto-install).
dev:
    nix develop
