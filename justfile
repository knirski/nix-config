# Task runner for the nix-config flake.
# Run `just` to list recipes; `just <recipe>` to run one.

# List every recipe with its doc comment.
default:
    @just --list

# Format all Nix/Python/shell/markdown with treefmt. No special prerequisites.
fmt:
    nix run path:.#formatter

# Check formatting + static analysis (deadnix, statix, typos, shellcheck, ...).
# Prerequisites: none (pure Nix build).
lint:
    nix build path:.#checks.x86_64-linux.pre-commit --no-link
    # Unlike the staged pre-commit hook, a manual lint scans the whole tree.
    nix run path:.#gitleaks -- detect --source . --no-git --redact --verbose

# Evaluate the whole flake (lints + builds every output incl. deploy checks).
# Prerequisites: /dev/kvm readable and writable.
check:
    @test -r /dev/kvm && test -w /dev/kvm || { echo "error: complete checks require readable and writable /dev/kvm" >&2; exit 1; }
    nix flake check path:.

# Run the four KVM-backed resilience tests required before merging changes.
# Prerequisites: /dev/kvm readable and writable.
test-resilience:
    nix build --no-link \
      path:.#checks.x86_64-linux.backup-unit-vm \
      path:.#checks.x86_64-linux.dns-dhcp-vm \
      path:.#checks.x86_64-linux.impermanence-vm \
      path:.#checks.x86_64-linux.clipboard-protocols

# Build a NixOS host's toplevel system. Pass host name as argument.
build host="soyo":
    nix build path:.#nixosConfigurations.{{host}}.config.system.build.toplevel

# Build the Ubuntu Home Manager activation package (standalone HM).
# Prerequisites: x86_64-linux Nix builder.
build-ubuntu:
    nix build path:.#homeConfigurations.ubuntu.activationPackage

# Build the macbook darwin closure (evaluates cross-platform on any arch).
build-macbook:
    nix build path:.#darwinConfigurations.macbook.config.system.build.toplevel

# Deploy to a host. Auto-detects the host type:
#   ubuntu  → home-manager switch
#   macbook → darwin-rebuild switch
#   others  → nixos-rebuild (local) or deploy-rs (remote)
deploy host="soyo":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{host}}" in
      ubuntu)
        home-manager switch --flake .#ubuntu ;;
      macbook)
        darwin-rebuild switch --flake .#macbook ;;
      *)
        CURRENT="$(hostname -s)"
        if [ "{{host}}" = "$CURRENT" ]; then
          sudo nixos-rebuild switch --flake .#{{host}}
        else
          nix develop '.#' -c deploy .#{{host}}
        fi ;;
    esac

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

# Run shared-env tests (needs zsh and bats installed).
test-shared-env:
    bats tests/shell/shared-env.bats

# Re-key all agenix secrets for every host after a key change.
# Prerequisites: agenix master identity configured at /etc/agenix-rekey/master-identity.
rekey:
    nix develop '.#' -c agenix rekey

# Refresh the sanitized, public topology overview. Updates docs/topology/overview.svg.
topology:
    topology=$(nix build path:.#topology-public-overview --no-link --print-out-paths); cp -f "$topology/overview.svg" docs/topology/overview.svg

# Build detailed operator diagrams locally and print their store path.
# Requires nix-topology inputs; output is not committed to the repo.
topology-operator-detailed:
    nix run path:.#topology-operator-detailed

# Enter the dev shell with all tooling (pre-commit hooks auto-install).
dev:
    nix develop
