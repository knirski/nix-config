# Testing and verification

The repository treats generated configuration, executable behavior, and
operator-only recovery as different evidence classes. The complete local gate
is `nix flake check path:. --keep-going`; focused checks are useful during
development, but do not replace it.

## KVM policy for VM checks

The DNS/DHCP, backup-unit, impermanence, and clipboard-protocol checks require
hardware virtualization. Their shared test wrapper enables nixpkgs' `qemu.forceAccel`,
so QEMU fails immediately when `/dev/kvm` is missing or inaccessible instead
of silently falling back to slow TCG emulation. Each guest also verifies the
KVM clock source, providing runtime evidence that acceleration is active.

The complete gate therefore requires a character device at `/dev/kvm` that is
readable and writable. Check it with
`test -c /dev/kvm && test -r /dev/kvm && test -w /dev/kvm`. A missing device is
a hard failure, never a reason to silently fall back to TCG or mark the VM tier
successful without executing it.

The set of KVM-classified checks lives in one place,
`lib/testing/kvm-checks.nix`; the `kvm-gate-drift` check (see Named checks
below) parses `ci.yml`'s `resilience` job and the justfile's
`test-resilience` recipe and fails if either one builds a different set of
names than that file declares, so the four checks below cannot silently
drift apart from what CI and `just` actually run.

## CI and local KVM gates

The selected GitHub `ubuntu-24.04` runner currently exposes accelerated KVM;
the pinned Determinate installer action configures it and has reported
`Accelerated KVM is enabled` in an actual repository run. CI still verifies the
device explicitly before running the strict behavior-test tier. If GitHub changes
the runner image or virtualization contract, the job fails closed instead of
quietly weakening coverage.

| Trigger class | Evidence |
| --- | --- |
| Every push and pull request | Static hooks, documentation/public-data/workflow/shell policies, formatting, the KVM-check drift gate, script contracts and topology freshness |
| Every push and pull request | Full no-build evaluation, pure invariants and isolated raw-restic integration |
| After static and evaluation pass | Complete Soyo and zbook closures; sanitized topology artifact |
| After static and evaluation pass | Four strict-KVM behavior tests; together with earlier tiers, every flake check is covered without rebuilding pure checks |
| Required before local handoff | The same complete KVM-backed flake gate |

The no-build tier runs first in a fresh job, before repository artifacts are
built. Its sole store prerequisite is the pair of tracked, encrypted
`secrets/rekeyed/<host>` source trees required by agenix-rekey's local storage
mode; CI adds those paths directly instead of building either host closure. A
narrower gate then evaluates project-owned dashboard and topology outputs with
`allow-import-from-derivation false`; build-time transformations are tested
separately. The full host configuration cannot disable IFD because agenix-rekey
uses it to resolve host-specific rekeyed secret files.

Run the hardware-accelerated resilience tier with:

```bash
test -r /dev/kvm -a -w /dev/kvm
just test-resilience
```

Then run `nix flake check path:. --keep-going` for the authoritative complete
repository gate. CI distributes that check set by evidence class; the KVM job
runs only behavior tests after its device preflight. See
[Verification layers](learning/verification-layers.md) for a
beginner-oriented explanation of why evaluation, builds, VM behavior and
physical recovery drills remain separate forms of evidence.

Cachix is configured read-only for pull requests, so they can substitute
previously published paths without receiving credentials. Every job that
needs Cachix substitution passes a `cachix-auth-token` input to the local
`setup-nix` action, but that input is itself an expression gated on
`github.event_name == 'push' && github.ref ==
'refs/heads/main'`: only a push to `main` resolves it to the real
`CACHIX_AUTH_TOKEN` secret and enables the authenticated, upload-capable
Cachix step. Every other trigger — including same-repo and fork pull
requests — resolves the input to an empty string, so no run driven by a pull
request ever holds the secret's value, regardless of whether it comes from
the same repository or a fork. The workflow token remains read-only. Closure
comparison was removed because a cached store-path string does not realize
its closure in a fresh runner's Nix store.

## Operational command contracts

The three operator-facing flake apps are tested with Bats. Bats was chosen over
another custom shell runner because named cases and per-test temporary
directories make cleanup and failure attribution explicit, while the tests
still execute the packaged commands as black boxes. Command doubles for SSH,
DNS, rage and Nix are themselves checked `writeShellApplication` packages;
tests never rewrite fixture executables in place.

| Contract | Expected exit status |
| --- | --- |
| Help, valid dry run, successful operation | 0 |
| Health check with one or more failed probes | 1 |
| Invalid host, role, interface, revision, secret source or confirmation | 2 |
| Interrupted secret mutation | 130; cleanup traps restore prior files |

`checks.script-contracts` covers argument boundaries, role selection, spaced
paths, exact subprocess argument vectors, timeout-like remote failures,
redaction, atomic rollback and dry-run non-mutation. Bats emits TAP in the
derivation log; CI does not currently consume JUnit, so no redundant report
artifact is generated.

## Shell boundaries

Shell code is checked at the boundary that actually executes it:

- NixOS `script`, `preStart`, `postStart`, `reload`, `preStop`, and `postStop`
  fragments use global `systemd.enableStrictShellChecks`. NixOS renders these
  through `writeShellApplication`, so warnings and undefined variables fail the
  system closure build.
- Repository-authored `ExecStart` helpers use `writeShellApplication` with
  explicit `runtimeInputs`. Tiny direct `ExecStart` commands use absolute Nix
  store paths; systemd does not invoke a shell for them.
- Standalone sources under `scripts/` and `tests/` are explicitly inventoried
  and passed directly to ShellCheck. A wrapper containing only `exec source.sh`
  would not count as checking the referenced source.

The `shell-boundaries` check rejects new standalone scripts until they are
classified, rejects repository `writeShellScript` calls, verifies that generated
unit fragments have strict checking enabled, and rejects non-absolute systemd
commands. Its mutation fixture demonstrates that an unchecked helper fails the
policy.

The three operator commands are first-class flake apps: `healthcheck`,
`recover-secrets`, and `set-tailscale-keys`. Their packages consume the actual
versioned source as `writeShellApplication.text`, rather than checking only a
one-line wrapper. `script-contracts` verifies help at an isolated command boundary,
pre-side-effect argument rejection, non-disclosing dry runs, and the absence of
automatic Git publication.

There are two upstream-owned exceptions:

- `dnsmasq`: the pinned module uses `mkdir -m 755 -p`, which triggers SC2174.
  The DHCP aspect separately declares lease-directory mode and ownership.
- `greetd`: the DMS greeter module's generated pre-start currently triggers
  SC2155, SC2162, and SC2035. The repository does not author that script.

The appliance DHCP and workstation Sway aspects own these scoped exceptions.
Repository-authored policy remains covered by evaluation and VM tests. Prefer
removing each exception once its pinned upstream module passes strict checking.

## Named checks

Every `checks.x86_64-linux.<name>` is defined in a `modules/parts/` module.
This table is the canonical index — when adding a check, add a row here.

| Check | What it asserts | Source | Type |
| ----- | --------------- | ------ | ---- |
| `backup-restic-integration` | restic can initialise a repo, backup, and check a snapshot | `backup-integration-check.nix` | Pure eval + shell script |
| `backup-unit-vm` | KVM VM: backup creates repo snapshots, readiness gates work | `backup-integration-check.nix` | KVM |
| `boot-generation-invariants` | Limine's `maxGenerations` is set, positive, and within the documented upper bound on every host | `boot-generation-invariants.nix` | Pure eval |
| `btrfs-alert-metric-contract` | The Btrfs usage/threshold Prometheus metric names emitted by `free-space-check` and consumed by the Grafana alert never drift apart | `observability-contract-checks.nix` | Pure eval + shell script |
| `clipboard-protocols` | Primary clipboard data-paste in Wayland | `clipboard-protocol-check.nix` | KVM |
| `dendritic-options` | Every `lanAppliance.services.*` option declared by the hosts that toggle it | `perSystem.nix` | Pure eval |
| `deploy-activate` | deploy-rs activation scripts don't error | `deploy.nix` (deploy-rs) | Pure eval |
| `deploy-schema` | deploy-rs node schema is valid | `deploy.nix` (deploy-rs) | Pure eval |
| `dns-dhcp-config` | Generated Blocky + dnsmasq config is valid; reservations match | `dns-dhcp-checks.nix` | Pure eval |
| `dns-dhcp-vm` | KVM VM: two nodes perform forward/reverse DNS, DHCP lease, restart | `dns-dhcp-vm-check.nix` | KVM |
| `docs-correctness` | Internal markdown links resolve; anchors exist; lifecycle is accurate; no orphans | `docs-checks.nix` | Pure eval |
| `failure-notification-invariants` | Reviewed operational units (scrub, `nix-gc`, free-space check, restic, btrbk, `grafana-alert-setup`, `nix-store-optimise`) all wire `OnFailure=ntfy-failure@%N.service`; `ntfy-failure@` itself never does; generated ntfy-failure@/smartd notify scripts carry title, unit/device identity, and read credentials from a file at runtime | `failure-notification-checks.nix` | Pure eval |
| `fmt-scope-contract` | treefmt enables exactly `nixfmt` and none of `ruff-format`/`black`/`shfmt`/`mdformat`/`prettier`, matching `just fmt`'s doc comment and the `formatting` row below; fails with an actionable message if a future edit silently widens treefmt's scope | `perSystem.nix` | Pure eval |
| `github-workflow-policy` | Workflow YAML uses pinned actions, least-privilege permissions, no mutable tags | `github-security-checks.nix` | Pure eval |
| `home-manager-channel-invariants` | Each host's evaluated Home Manager release actually tracks the Nixpkgs channel its assembler intends | `home-manager-channel-checks.nix` | Pure eval |
| `host-role-invariants` | Soyo has appliance role + no GUI; zbook has workstation role + GUI; base has no role bias | `host-role-invariants.nix` | Pure eval |
| `impermanence-vm` | KVM VM: root wipes on boot; only persisted state survives | `impermanence-vm-check.nix` | KVM |
| `impermanence-missing-early-persist` | Unpersisted early-boot paths fail with an error | `impermanence-vm-check.nix` | Pure eval |
| `initrd-recovery-invariants` | Initrd SSH unlock, TPM, and break-glass paths have all required options | `initrd-invariants.nix` | Pure eval |
| `kvm-gate-drift` | The KVM check set declared in `lib/testing/kvm-checks.nix` cannot drift from what `ci.yml`'s `resilience` job and `just test-resilience` actually build | `kvm-gate-drift-check.nix` | Pure eval + shell script |
| `lan-inventory` | Python unit tests for  LAN inventory collector | `perSystem.nix` | Pure eval + Python |
| `maintenance-paths` | Required tmpfiles rule exists for free-space check path | `perSystem.nix` | Pure eval |
| `nixpkgs-policy-invariants` | Soyo's evaluated `nixpkgs.config` carries no insecure-package allowance; every `lib/insecure-package-exceptions.nix` entry has structured rationale/owner/review metadata; zbook/macbook/ubuntu's evaluated `permittedInsecurePackages` match the registry exactly | `nixpkgs-policy-checks.nix` | Pure eval |
| `persistence-invariants` | Every persisted path exists in the host config; mode/owner are sane | `persistence-invariants.nix` | Pure eval |
| `pre-commit` | Lint: deadnix, statix, typos, end-of-file-fixer, merge-conflicts, actionlint, shellcheck, ruff, markdownlint | `perSystem.nix` | Git hook |
| `public-repository-data` | No secrets, hostnames, or private IPs in public SVGs | `public-repo-checks.nix` | Pure eval |
| `reservation-validation` | Reservations have valid MACs, IPs, and no duplicates | `reservation-checks.nix` | Pure eval |
| `script-contracts` | Operator commands (healthcheck, recover-secrets, set-tailscale-keys) handle valid/invalid/dry-run/interrupted args correctly | `script-tests.nix` | Shell (Bats) |
| `shell-boundaries` | No `writeShellScript` calls; generated unit fragments have strict checking | `shell-checks.nix` | Pure eval |
| `soyo-guest-isolation` | Guest services on Soyo have MemoryMax, CPUQuota, Nice applied | `soyo-guest-isolation.nix` | Pure eval |
| `systemd-hardening-invariants` | Applicable systemd services have basic hardening (ProtectSystem, PrivateTmp, etc.) | `systemd-hardening-checks.nix` | Pure eval |
| `topology-freshness` | Committed `docs/topology/overview.svg` matches the current stable state | `topology-checks.nix` | Pure eval |
| `dashboard-renderer` | Python unit tests for the observability dashboard renderer | `perSystem.nix` | Pure eval + Python |
| `formatting` | treefmt formatting check — Nix only (`nixfmt`); Python/shell/Markdown are lint-checked by the `ruff`/`shellcheck`/`markdownlint` pre-commit hooks instead, not auto-formatted. treefmt-nix's own auto-generated `checks.treefmt` is disabled (`flakeCheck = false`) so this is the repo's only treefmt check | `perSystem.nix` | Pure eval |

### KVM tests

The four KVM-requiring checks (`dns-dhcp-vm`, `backup-unit-vm`, `impermanence-vm`,
`clipboard-protocols`) run in a sandbox QEMU with `qemu.forceAccel` enabled.
They require `/dev/kvm` to be readable and writable.

### Shell contract tests

`script-contracts` uses Bats with command doubles. Each operator command is
tested against: help, valid dry-run, successful operation, failed probes
(exit 1), invalid arguments (exit 2), and interruption (exit 130 cleanup).

## Adding a check

Every new check follows the same pattern:

1. Create the assertion module in `modules/parts/<name>.nix` as a flake-parts
   module that registers `checks.<system>.<name>` under `perSystem`.
2. For a **pure eval check** (fast, /dev/kvm not needed): use
   `pkgs.runCommand` with inline Nix assertions. Example:

   ```nix
   checks.my-check = pkgs.runCommand "my-check" {
     inherit ok; # a boolean computed in Nix
     passAsFile = [ "failures" ];
     inherit failures;
   } ''
     if [ "$ok" != "1" ]; then
       echo "Failures:" >&2; cat "$failuresPath" >&2; exit 1
     fi
     touch "$out"
   '';
   ```

3. For a **shell script check**: use `pkgs.writeShellApplication` as the
   executable and `pkgs.runCommand` as the check derivation. Wire up Bats
   if the test involves argument parsing.
4. For a **KVM behaviour test**: use the shared `runKvmTest` from
   `lib/testing/run-kvm-test.nix` which enforces `qemu.forceAccel`.
5. Wire the check into CI: add the check name to the appropriate step in
   `.github/workflows/ci.yml` (static tier for lint/policy, evaluation for
   pure asserts, resilience for KVM tests). Add it to `just test-resilience`
   if KVM.
6. Add a row to the **Named checks** table above.

### Registering the check in CI

Edit `.github/workflows/ci.yml`:

- **Static tier** — add to the `nix build --no-link` list in the `static` job
  for checks that run quickly without building a host closure.
- **Evaluation tier** — add to the `nix build --no-link` list in the
  `evaluation` job for eval-only checks (most new checks go here).
- **Resilience tier** — add to the KVM list in the `resilience` job.
- **Build tier** — not for individual checks; the host closure build covers
  compilation.

The ci.yml steps list every check by name. If the new check is expensive or
has unusual prerequisites (e.g. `dev/kvm`), confirm which tier fits.

## Evidence limits

VM checks cover isolated software behaviour, including DNS/DHCP, backup, and
impermanence. They do not prove physical TPM measurements, Secure Boot firmware
behaviour, real LAN recovery, or restore operations against production data.
Those remain explicit operator-led drills in the relevant runbooks.

Automated checks (pure evaluation, VM, shell contract) are the first line of
confidence. Anything that depends on hardware, physical access, or production
state is explicitly listed as a manual-only verification in `AGENTS.md` and the
host-specific runbooks.
VM checks cover isolated software behaviour, including DNS/DHCP, backup, and
impermanence. They do not prove physical TPM measurements, Secure Boot firmware
behaviour, real LAN recovery, or restore operations against production data.
Those remain explicit operator-led drills in the relevant runbooks.

Automated checks (pure evaluation, VM, shell contract) are the first line of
confidence. Anything that depends on hardware, physical access, or production
state is explicitly listed as a manual-only verification in `AGENTS.md` and the
host-specific runbooks.
