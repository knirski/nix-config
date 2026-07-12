# Task runner for the nix-config flake.
# Run `just` to list recipes; `just <recipe>` to run one.

# List every recipe with its doc comment.
default:
    @just --list

# Format all Nix/Python/shell/markdown with treefmt.
fmt:
    nix run path:.#formatter

# Check formatting + static analysis (deadnix, statix, typos, shellcheck, ...).
lint:
    nix build path:.#checks.x86_64-linux.pre-commit --no-link
    # Unlike the staged pre-commit hook, a manual lint scans the whole tree.
    nix run path:.#gitleaks -- detect --source . --no-git --redact --verbose

# Evaluate the whole flake (lints + builds every output incl. deploy checks).
check:
    @test -r /dev/kvm && test -w /dev/kvm || { echo "error: complete checks require readable and writable /dev/kvm" >&2; exit 1; }
    nix flake check path:.

# Run the three KVM-backed resilience tests required before merging changes.
test-resilience:
    nix build --no-link \
      path:.#checks.x86_64-linux.backup-unit-vm \
      path:.#checks.x86_64-linux.dns-dhcp-vm \
      path:.#checks.x86_64-linux.impermanence-vm

# Build a host's toplevel system.
build host="soyo":
    nix build path:.#nixosConfigurations.{{host}}.config.system.build.toplevel

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
    nix build path:.#checks.x86_64-linux.dendritic-options --no-link --print-out-paths

# Re-key all agenix secrets for every host after a key change.
rekey:
    nix develop '.#' -c agenix rekey

# Refresh the sanitized, public topology overview.
topology:
    topology=$(nix build path:.#topology-public-overview --no-link --print-out-paths); cp -f "$topology/overview.svg" docs/topology/overview.svg

# Build detailed operator diagrams locally and print their store path.
topology-operator-detailed:
    nix build path:.#topology-operator-detailed --no-link --print-out-paths

# Enter the dev shell with all tooling (pre-commit hooks auto-install).
dev:
    nix develop
