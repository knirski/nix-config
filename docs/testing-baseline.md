# Testing baseline

> **Status: Historical evidence.** This is a dated measurement, not the current
> check inventory. See [testing.md](testing.md) for the active verification
> policy.

Measured on 2026-07-12 at commit
`4cd1f2f2ec7b047720784f0cf0507c615892801b`, with the intentional uncommitted
working tree described below. This is evidence, not a claim that `HEAD` alone
has the same behavior: every Nix command used `path:.` so new and modified files
were included.

## Executive status

- Nix 2.34.7 on Linux 7.1.3, `x86_64-linux`.
- `/dev/kvm` was readable and writable. NixOS VM tests can therefore use KVM,
  but a CI runner may not provide it and should be sized for emulation or skip
  the test only through an explicit policy.
- Both complete host closures built successfully with `--no-link`.
- The whole-repository gate **failed** in `pre-commit`: the untracked
  `docs/router-recommendation.md` has no H1 and contains the misspelling
  a misspelling. This baseline task deliberately did not fix implementation or
  user-owned files.
- The other derivations needed by that warm-cache run evaluated successfully;
  only `pre-commit`, `treefmt`, and `topology-freshness` needed rebuilding.
- Nix emitted the known non-failing warnings for the custom `agenix-rekey` and
  `deploy` flake outputs.

The required green baseline is therefore not established yet. Later work must
fix the source document and rerun the exact full gate; it must not reinterpret
this result as a pass.

## Working-tree provenance

The baseline included the following intentional, user-owned changes:

```text
Modified: .github/workflows/ci.yml, AGENTS.md, README.md,
docs/install-soyo.md, docs/learning/README.md,
docs/learning/design-journey.md, docs/secrets.md,
docs/superpowers/specs/soyo-dns-dhcp-appliance.md,
docs/topology/main.svg, docs/topology/network.svg, flake.nix,
hosts/soyo/DEPLOY.md, hosts/soyo/backup.nix, hosts/soyo/dhcp.nix,
hosts/soyo/networking.nix, hosts/soyo/reservations.nix, justfile,
modules/nixos/backup.nix, modules/nixos/base.nix,
modules/nixos/nvidia.nix, modules/nixos/observability.nix,
modules/nixos/server.nix, modules/nixos/tailscale.nix,
modules/nixos/workstation.nix, modules/parts/perSystem.nix,
modules/parts/soyo.nix, modules/parts/topology.nix,
modules/parts/zbook.nix, scripts/healthcheck.sh,
scripts/recover-secrets.sh, scripts/set-tailscale-keys.sh

Untracked: docs/gap-report.md, docs/optional-work-plan.md,
docs/router-recommendation.md,
docs/superpowers/plans/2026-07-12-correctness-resilience-docs.md,
hosts/soyo/network-policy.nix, lib/network/,
modules/parts/dns-dhcp-checks.nix,
modules/parts/dns-dhcp-vm-check.nix,
modules/parts/healthcheck-tests.nix,
modules/parts/host-role-invariants.nix,
modules/parts/persistence-invariants.nix,
modules/parts/reservation-checks.nix,
modules/parts/soyo-guest-isolation.nix,
modules/parts/topology-checks.nix, scripts/tests/
```

## Flake check inventory

`nix eval --json path:.#checks.x86_64-linux --apply builtins.attrNames` returned
exactly these 15 attributes. Each appears once in this inventory.

| Check | Contract |
| --- | --- |
| `dendritic-options` | Expected host option namespaces exist |
| `deploy-activate` | deploy-rs activation check |
| `deploy-schema` | deploy-rs profile schema check |
| `dns-dhcp-config` | Generated Blocky/dnsmasq policy agrees |
| `dns-dhcp-vm` | Two-node DNS, DHCP, PTR, and restart test |
| `formatting` | Clean-source treefmt check; currently aliases `treefmt` |
| `healthcheck-tests` | Hermetic health-check command behavior |
| `host-role-invariants` | Server/workstation role boundaries |
| `lan-inventory` | Python LAN inventory unit tests |
| `persistence-invariants` | Persistence, ownership, backup, and snapshot wiring |
| `pre-commit` | Repository hook suite |
| `reservation-validation` | Reservation schema and network-policy validation |
| `soyo-guest-isolation` | Explicit guest-unit resource limits |
| `topology-freshness` | Committed SVGs equal generated output |
| `treefmt` | Clean-source treefmt check |

The negative control
`nix build path:.#checks.x86_64-linux.this-check-does-not-exist --no-link`
failed with an attribute-not-provided error. Missing check names are not silently
accepted.

## Commands and timings

These are warm-store wall-clock measurements from one machine. They are useful
for detecting large regressions locally, not for predicting a cold GitHub
runner. Store hits made most individual checks effectively evaluation-only, so
there is no honest per-check ranking from this run.

| Command | Result | Wall time | Notes |
| --- | --- | ---: | --- |
| `nix flake check path:. --keep-going --show-trace` | Failed | 17.74 s | `pre-commit` Markdownlint and typos failures described above |
| `nix build path:.#nixosConfigurations.soyo.config.system.build.toplevel --no-link` | Passed | 4.47 s | Warm store; closure is 6.0 GiB |
| `nix build path:.#nixosConfigurations.zbook.config.system.build.toplevel --no-link` | Passed | 6.31 s | Warm store; closure is 16.2 GiB |

The largest artifacts are the host closures, especially zbook. The VM test is
the check most likely to dominate a cold run because it builds two machine
closures and boots guests; record cold CI timings before using duration to
split or skip it.

## CI inventory

`.github/workflows/ci.yml` runs on pushes and pull requests to `main`, plus
manual dispatch. Concurrent obsolete runs are cancelled. Workflow permissions
are `contents: read`.

| Job | Current work |
| --- | --- |
| `lint` | Builds `pre-commit`, then scans the checkout with gitleaks |
| `eval` | Runs store GC, then the full `nix flake check` |
| `build (soyo)` | Builds the Soyo closure and attempts a cached closure diff |
| `build (zbook)` | Builds the zbook closure and attempts a cached closure diff |
| `topology` | After `eval`, builds and uploads generated SVGs |

This is four YAML jobs and five effective jobs after the build matrix expands.
Every job repeats checkout and Nix/cache setup. Actions currently use mutable
major-version tags. The full `eval` gate overlaps the dedicated lint work, and
the public topology artifact increases the visibility of detailed network data.

## Script and generated-shell inventory

Tracked source scripts:

- `scripts/healthcheck.sh`
- `scripts/recover-secrets.sh`
- `scripts/set-tailscale-keys.sh`
- `scripts/tests/healthcheck_test.sh`

Generated or inline systemd shell exists in:

- `modules/nixos/laptop.nix`
- `modules/nixos/persistence.nix`
- `modules/nixos/backup.nix`
- `modules/nixos/maintenance.nix`
- `modules/nixos/tailscale.nix`

`modules/nixos/observability.nix` packages the LAN inventory exporter with
`writeShellApplication`; `modules/parts/perSystem.nix` packages the health
check, but its wrapper only executes the source file and does not itself prove
that source was strictly checked. This inventory is the input to the shell
policy tasks; it does not yet judge each unit's required sandbox directives.

## Documentation and public diagrams

Current Markdown entry points and runbooks are:

- `README.md`
- `docs/backup-and-restore.md`
- `docs/gap-report.md`
- `docs/hyprland-desktop.md`
- `docs/install-soyo.md`
- `docs/learning/README.md`
- `docs/learning/design-journey.md`
- `docs/optional-work-plan.md`
- `docs/recovery.md`
- `docs/router-recommendation.md`
- `docs/secrets.md`
- `docs/update-and-rollback.md`
- three dated implementation plans under `docs/superpowers/plans/`, plus this
  plan
- three design/specification documents under `docs/superpowers/specs/`

There is no `docs/README.md` hub. The two committed public diagrams total
2,444,760 bytes (`main.svg`: 1,680,667; `network.svg`: 764,093). A conservative
text scan found IPv4-like tokens and MAC-like tokens in both. It also found URL
tokens, which include normal SVG/XML namespaces and therefore are not by
themselves proof of active content. The later public-data task must parse SVG
structure rather than rely only on regular expressions.

## GitHub issue and security posture

Read-only authenticated queries confirmed:

- repository: `knirski/nix-config`, public, default branch `main`;
- issues enabled; the only issue is open issue
  [#2, Bootstrap Soyo from NixOS Live USB](https://github.com/knirski/nix-config/issues/2);
- `main` has no branch protection;
- Actions allow all actions and do not require SHA pinning;
- Dependabot alerts and security updates are disabled;
- secret scanning, validity checks, non-provider patterns, and push protection
  are disabled;
- no code-scanning analysis exists;
- repository deletion-on-merge is disabled.

The token used for the audit lacked `admin:repo_hook`, so one code-scanning API
response also mentioned insufficient scope. The repository metadata and the
specific 404/403 feature responses consistently establish the disabled or
unconfigured state; no GitHub setting was changed.

## Baseline gate to reproduce

Run from the repository root with adequate Nix-store space:

```bash
nix flake check path:. --keep-going --show-trace
nix build path:.#nixosConfigurations.soyo.config.system.build.toplevel --no-link
nix build path:.#nixosConfigurations.zbook.config.system.build.toplevel --no-link
nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose
git diff --check
```

On a runner without KVM, expect the VM test to be much slower. Do not silently
drop it; either provide acceleration or make any reduced gate an explicit,
documented tier with the full test required elsewhere.
