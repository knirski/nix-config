# Repository Assessment Remediation Plan

Date: 2026-07-22

Status: active; implementation has not started

## Goal

Close every correctness, operational, security, portability, CI, and
documentation gap found in the 2026-07-22 repository assessment while
preserving the architectural decisions in the
[canonical Soyo design](../specs/soyo-dns-dhcp-appliance.md).

The end state is not merely a green evaluation. It must provide runtime or
behavioral evidence for service ordering, alert contracts, clipboard
protocols, backup health, role boundaries, and CI credential boundaries. The
production DNS and DHCP paths must remain isolated from all guest and
workstation concerns.

## Authority and predecessor ownership

This is the repository's sole active implementation plan. It supersedes the
[2026-07-12 correctness and resilience plan](2026-07-12-correctness-resilience-docs.md)
and the earlier
[repository gaps and improvements plan](../specs/repository-gaps-and-improvements.md).
Those documents remain available as dated planning evidence, but their task
lists are frozen and must not be implemented independently.

Any predecessor item that still appears relevant must first be revalidated
against the current repository and mapped into a work item here. Architecture
authority remains with the canonical Soyo design and implemented subsystem
specifications; superseding an execution plan does not supersede those design
decisions.

## Scope and completion map

| Assessment finding | Work item |
| --- | --- |
| Tailscale authentication orders against a nonexistent unit | C1 |
| Grafana queries metric names that the producer never emits | C2 |
| Soyo mixes stable Nixpkgs with unstable Home Manager | C3 |
| Clipboard KVM test fails and is absent from the explicit CI KVM set | C4 |
| Maintenance and SMART failures are not fully reported | O1 |
| Limine generations are unbounded | O2 |
| Healthcheck does not prove backup freshness or all-probe health | O3 |
| Soyo receives a GitHub token and workstation/agent tooling | R1 |
| Shared Home Manager base assumes Linux GUI facilities | R2 |
| Cachix and PR Agent permissions are broader than required | S1 |
| Required checks do not include the complete supported KVM/host matrix | S2 |
| Vendored npm dependency policy and automation are incomplete | S3 |
| Global insecure/unfree allowances are broader than their consumers | S4 |
| macbook package, terminal, shell, and runbook contracts disagree | H1 |
| Ubuntu agenix, login-shell, and desktop-session instructions are invalid | H2 |
| Reusable backup and observability aspects contain Soyo-specific values | M1 |
| Dated assessment documents and status claims have drifted | D1 |
| `just` and formatter descriptions promise behavior they do not provide | D2 |

The following are deliberate roadmap choices, not defects to implement here:
full IPv6 DNS/DHCP, RAID1, offsite NAS replication, M4 guest applications, and
a second DNS/DHCP appliance. D1 must keep these visibly marked as accepted
risks or deferred work so they are not rediscovered as regressions.

## Safety and repository constraints

Every implementation task must:

1. read [`AGENTS.md`](../../../AGENTS.md), this plan, and the canonical design;
2. verify that its reported gap still exists before editing;
3. preserve the dendritic aspect pattern and keep host directories focused on
   hardware and host data;
4. keep `modules/nixos/base.nix` and `modules/home/base.nix` role-neutral;
5. use `apply_patch` for source edits and preserve unrelated worktree changes;
6. never hand-edit `flake.lock`, `secrets/rekeyed/`, or `hosts/*/facter.json`;
7. update a flake input only with `nix flake update <input>`;
8. use fixtures instead of production secrets, NAS targets, or live ntfy
   endpoints in automated tests;
9. run the narrow acceptance tests first, then the repository gates in G1;
10. not deploy, reboot, rekey, change GitHub settings, send notifications, or
    run a live restore without separate authorization.

When integrated Home Manager uses `useGlobalPkgs = true`, package overlays must
remain at the NixOS or nix-darwin package-set boundary. Do not move overlays
into a Home Manager aspect where they would be ignored.

## Baseline evidence

Record this baseline in the first implementation PR so later work can compare
against it:

- `just lint` passes, including the current-tree gitleaks scan.
- `nix flake check path:. --no-build --show-trace` evaluates, but warns that
  Home Manager 26.11 and Nixpkgs 26.05 are mismatched for Soyo.
- Soyo and zbook system closures build.
- The Ubuntu Home Manager activation package builds.
- Fresh KVM builds pass `backup-unit-vm`, `dns-dhcp-vm`, and
  `impermanence-vm`.
- A forced fresh KVM build of `clipboard-protocols` fails in the PRIMARY
  selection scenario.
- The macbook configuration evaluates on Linux; its actual Darwin closure is a
  macOS CI responsibility until target hardware is available.

Do not treat a cached derivation as evidence that a formerly failing behavior
has been repaired. For C4 and other regression repairs, force one fresh build
or change the test derivation in a reviewable way.

## Execution order

```text
B0 baseline
├── C1 Tailscale ordering ───────┐
├── C2 metric contract ──────────┴── O1 notification coverage ── O3 healthcheck
├── C3 HM release split ── R1 role packages/secrets ── R2 portable HM base
│                                                      ├── H1 macbook contract
│                                                      └── H2 Ubuntu contract
├── C4 clipboard KVM ────────────┐
├── S1 CI least privilege ───────┴── S2 complete CI/required checks
├── O2 boot-generation limit
├── S3 npm supply chain ──────────── S4 package policy scope
└── M1 reusable service options

Completed implementation work ── D1 documentation reconciliation
D1 + C4 + S2 ──────────────────── D2 workflow wording

All repository-local work ── G1 final gates ── G2 authorized live validation
```

B0 is baseline evidence rather than a source-change PR. Every other work item
has its own PR in the suggested sequence, including O1 and O2: they affect
different runtime boundaries and must be independently reviewable and
revertible. Do not bundle work items merely to reduce the PR count.

## B0 — Capture the baseline and ownership table

Priority: P0

Dependencies: none

Likely files:

- this plan
- no production configuration

Steps:

1. Confirm the worktree state and record any pre-existing user changes.
2. Run the baseline commands listed above and retain concise command/output
   evidence in the PR description, not generated repository files.
3. Assign each changed file to one work item before editing. Split overlapping
   changes rather than letting a broad refactor obscure the defect being fixed.
4. Confirm `/dev/kvm` is readable and writable before starting C4 or G1.

Acceptance:

- The PR or implementation log distinguishes cached evaluation evidence from
  fresh behavioral evidence.
- No generated secret, hardware inventory, result link, or diagnostic log is
  committed.

## C1 — Correct and verify Tailscale authentication ordering

Priority: P0

Dependencies: B0

Likely files:

- [`modules/nixos/tailscale.nix`](../../../modules/nixos/tailscale.nix)
- [`modules/parts/systemd-hardening-checks.nix`](../../../modules/parts/systemd-hardening-checks.nix)
- a focused fixture under `modules/_tests/systemd/` if needed

Steps:

1. Change `tailscale-auth` ordering and wants from `tailscale.service` to the
   evaluated NixOS daemon unit, `tailscaled.service`.
2. Keep authentication after agenix activation so the auth-key path exists.
3. Replace the current test that merely repeats the misspelled string with a
   contract that also proves the referenced service exists in the evaluated
   service set.
4. Add a negative fixture: restoring `tailscale.service` must fail the focused
   invariant.
5. Evaluate `after`, `wants`, `wantedBy`, timeout, and restart policy from the
   real Soyo configuration.
6. If a fixture VM can inject a fake Tailscale daemon and CLI cheaply, prove
   that authentication starts only after daemon readiness. Otherwise keep the
   remaining first-boot check in G2.

Acceptance:

- `tailscale-auth.after` contains `tailscaled.service` and
  `agenix-activation.service`.
- `tailscale-auth.wants` contains `tailscaled.service`.
- The test proves `tailscaled` is an evaluated systemd service.
- The misspelled dependency mutation fails for the intended reason.
- No authentication key appears in a store path, command output, or test log.

Suggested commit: `fix(tailscale): order authentication after tailscaled`

## C2 — Make Btrfs metrics and Grafana alerts one contract

Priority: P0

Dependencies: B0

Likely files:

- [`modules/nixos/maintenance.nix`](../../../modules/nixos/maintenance.nix)
- [`lib/observability/grafana-alert-setup.nix`](../../../lib/observability/grafana-alert-setup.nix)
- a small shared helper under `lib/observability/`
- observability or maintenance checks under `modules/parts/`

Steps:

1. Define the Btrfs usage and threshold metric names once in a reusable helper
   outside the import-tree module tree.
2. Interpolate those names into both the Prometheus textfile output and the
   Grafana alert expression. Preserve the `host` label and use an explicit
   label match or vector matching so multi-host data cannot be compared
   accidentally.
3. Add a pure contract test that inspects the generated metric exposition and
   generated alert expression.
4. Add negative fixtures that rename either producer metric or consumer query;
   each mutation must fail.
5. Keep the direct low-space ntfy path independent of Grafana so one failed
   guest service cannot suppress the appliance-local warning.

Acceptance:

- Both emitted series are referenced by the generated Grafana expression.
- The expression matches the correct host label.
- Producer/consumer drift is mechanically rejected.
- No `soyo_` prefix remains unless the producer deliberately emits it.

Suggested commit: `fix(observability): share the btrfs alert metric contract`

## C3 — Align Home Manager with each host's Nixpkgs release

Priority: P0

Dependencies: B0

Likely files:

- [`flake.nix`](../../../flake.nix)
- `flake.lock`, updated only by the approved flake command
- [`modules/parts/soyo.nix`](../../../modules/parts/soyo.nix)
- [`modules/parts/zbook.nix`](../../../modules/parts/zbook.nix)
- [`modules/parts/macbook.nix`](../../../modules/parts/macbook.nix)
- [`modules/parts/ubuntu.nix`](../../../modules/parts/ubuntu.nix)
- [`modules/parts/hm-flake-module.nix`](../../../modules/parts/hm-flake-module.nix)
- host-role and dendritic evaluation checks

Steps:

1. Keep the existing `home-manager` input following `nixpkgs-unstable` for
   zbook, macbook, Ubuntu, and the Home Manager flake-parts output module.
2. Add `home-manager-stable` from `release-26.05`, following `nixpkgs`.
3. Update only Soyo to import `home-manager-stable.nixosModules.home-manager`.
4. Update the lock with `nix flake update home-manager-stable`; do not edit it
   manually or update unrelated inputs.
5. Remove `home.enableNixpkgsReleaseCheck = false` only where it is no longer
   needed. Do not use the setting to hide a real mismatch.
6. Add an evaluated invariant proving Soyo's HM release tracks stable while the
   three unstable hosts use the unstable input.
7. Rebuild the Soyo closure and Ubuntu activation package; evaluate the zbook
   and macbook assemblers before the full G1 builds.

Acceptance:

- Soyo evaluation emits no Home Manager/Nixpkgs release mismatch warning.
- Each Home Manager input follows exactly one intended Nixpkgs input.
- Soyo, zbook, Ubuntu, and macbook continue to expose their expected outputs.
- `flake.lock` contains only the intended input addition/update.

Suggested commit: `fix(flake): align home manager inputs with host channels`

## C4 — Repair and enforce the clipboard KVM test

Priority: P0

Dependencies: B0

Likely files:

- [`modules/parts/clipboard-protocol-check.nix`](../../../modules/parts/clipboard-protocol-check.nix)
- [`justfile`](../../../justfile)
- [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml)
- [`docs/testing.md`](../../testing.md)

Steps:

1. Reproduce the PRIMARY-selection failure with a fresh KVM build and retain
   the failing subtest name and compositor/client logs.
2. Inspect the actual MIME offers for regular and PRIMARY selections. Do not
   assume `text/plain` when the client offers only a charset-qualified type.
3. Check `wl-copy` process lifetime and daemonization. Use foreground mode or
   another explicit lifetime contract so the test waits for the real selection
   owner rather than an exited launcher.
4. Keep regular and PRIMARY ownership independent and assert both contents
   before either paste-once owner exits.
5. Preserve the regular text, binary MIME, and clear-selection scenarios.
6. Add `clipboard-protocols` to `just test-resilience` and the CI resilience
   job. Update every “three KVM tests” statement to derive or state the actual
   four-test set.
7. Run the repaired test twice from a fresh derivation to detect timing flakes.

Acceptance:

- All four clipboard scenarios pass under KVM twice.
- Replacing the PRIMARY read with the regular selection, or changing the
  expected PRIMARY value, fails the test.
- The explicit local and CI KVM sets contain every KVM-classified flake check.
- CI still fails closed when `/dev/kvm` is unavailable.

Suggested commit: `fix(test): make primary clipboard coverage deterministic`

## O1 — Complete failure and SMART notification coverage

Priority: P1

Dependencies: C1, C2

Likely files:

- [`modules/nixos/maintenance.nix`](../../../modules/nixos/maintenance.nix)
- [`modules/nixos/backup.nix`](../../../modules/nixos/backup.nix)
- [`modules/parts/systemd-hardening-checks.nix`](../../../modules/parts/systemd-hardening-checks.nix)
- service-hardening and testing documentation

Steps:

1. Enumerate the operational jobs whose silent failure matters: Btrfs scrub,
   Nix GC, store optimization, free-space check, restic, btrbk, and any alert
   provisioning helper needed for recovery visibility.
2. Resolve the canonical design's phrase “any failed unit” explicitly. Prefer
   a reviewed list of operational and critical units over an unsafe global
   drop-in that can recurse or notify for irrelevant transient units; update
   the design wording if this narrows the original intent.
3. Apply `OnFailure=ntfy-failure@%N.service` to the reviewed list. Keep the
   notification template self-excluded and rate-limited.
4. Add a smartd notification command using supported current NixOS smartd
   options. It must read ntfy credentials from files at runtime, accept smartd
   event metadata safely, and avoid secret values in argv or logs.
5. Stub the network boundary in automated tests and assert notification title,
   unit/device identity, and non-secret message content.
6. Add a pure invariant for the monitored-unit list plus negative fixtures
   removing each critical notification edge.
7. Document the distinction between a threshold alert, a unit execution
   failure, a SMART warning, and total-host outage monitoring.

Acceptance:

- Every reviewed operational unit has the expected failure edge.
- The notification unit itself cannot recurse through `OnFailure`.
- A fixture unit failure and fixture SMART warning reach the stub transport.
- Credentials are read from agenix paths and never serialized into the Nix
  store or journal assertion output.
- External Uptime Kuma remains the documented detector for total host loss.

Suggested commit: `feat(maintenance): complete operational failure alerts`

## O2 — Bound boot generations

Priority: P1

Dependencies: B0

Likely files:

- [`hosts/soyo/boot.nix`](../../../hosts/soyo/boot.nix)
- [`hosts/zbook/boot.nix`](../../../hosts/zbook/boot.nix)
- a boot invariant under `modules/parts/`
- recovery or update documentation

Steps:

1. Confirm the current Limine option name and semantics in the locked Nixpkgs
   option set.
2. Set a deliberate limit of 10 generations on both NixOS hosts unless an
   evaluated size/recovery argument justifies a different documented value.
3. Add an invariant that Soyo's value is non-null, positive, and no greater
   than the documented upper bound.
4. Explain that the limit bounds ESP/menu growth but does not replace Nix GC or
   the persisted Secure Boot signing keys.
5. Keep rollback and break-glass documentation clear about the number of old
   generations expected to remain available.

Acceptance:

- `boot.loader.limine.maxGenerations` evaluates to the documented bound.
- A null, zero, or excessive mutation fails the invariant.
- Soyo and zbook closures build without changing TPM PCR policy.

Suggested commit: `fix(boot): bound retained limine generations`

## O3 — Make the healthcheck prove backup and probe health

Priority: P1

Dependencies: O1

Likely files:

- [`scripts/healthcheck.sh`](../../../scripts/healthcheck.sh)
- healthcheck Bats tests under `tests/shell/`
- [`docs/testing.md`](../../testing.md)
- [`docs/backup-and-restore.md`](../../backup-and-restore.md)

Steps:

1. Check the restic timer is enabled and the latest completed backup is
   successful and no older than a documented threshold derived from its
   schedule.
2. Check the host-specific btrbk timer on both Soyo and zbook.
3. Prefer stable machine-readable signals: evaluated timer names, systemd
   properties, restic success metrics, or snapshot timestamps. Avoid parsing
   decorative human output.
4. Replace `grep ... | head` blackbox checks with a Prometheus API query parsed
   by `jq` that requires every expected target in the selected job to be
   healthy and fails on an empty target set.
5. Add Bats fixtures for stale backup, failed last backup, absent target,
   partially failed targets, all targets healthy, and host-specific timers.
6. Keep live restic restore validation in the manual drill; a successful timer
   alone must not be described as proof of restorability.

Acceptance:

- A stale or failed backup makes the healthcheck fail with a specific message.
- A single failed blackbox target fails the relevant section.
- An empty Prometheus result cannot pass.
- Both host roles check their declared snapshot timer.
- Existing healthcheck tests and ShellCheck remain green.

Suggested commit: `feat(healthcheck): verify backup freshness and every probe`

## R1 — Separate appliance administration from workstation development

Priority: P1

Dependencies: C3

Likely files:

- [`modules/home/base.nix`](../../../modules/home/base.nix)
- a new `modules/home/development.nix` aspect
- [`modules/nixos/users.nix`](../../../modules/nixos/users.nix)
- a workstation-scoped NixOS secret aspect or host declaration
- Soyo, zbook, macbook, and Ubuntu assemblers
- host-role invariants

Steps:

1. Inventory every package and program in `homeManager.base` and classify it as
   universal administration, development/agent tooling, or desktop tooling.
2. Move `command-code`, Claude Code, Codex, OpenCode, language servers, and
   similar developer-only tools into `aspects.homeManager.development`.
3. Enable the development aspect on zbook, macbook, and Ubuntu. Keep Soyo on a
   minimal administration base unless a tool has a documented recovery need.
4. Move `github-token` out of the shared NixOS users aspect. Declare and export
   it only on hosts that enable the development/workstation capability.
5. Ensure Bash and Zsh use the same optional token-loading behavior without
   reading the file during evaluation.
6. Add closure/invariant checks proving Soyo has neither the token secret nor
   the named agent packages while workstation hosts retain their intended
   tools.
7. Update `docs/secrets.md` because the secret's host recipient and activation
   scope changes, even if the master `.age` file remains unchanged.

Acceptance:

- Soyo's evaluated secrets do not include `github-token`.
- Soyo's Home Manager package/program set excludes the reviewed agent tools.
- Workstation outputs still provide the intended development environment.
- No master or rekeyed secret is edited by hand.
- Any required recipient change is performed later with `agenix rekey` under
  explicit authorization.

Suggested commit: `refactor(home): isolate development tools and credentials`

## R2 — Make the Home Manager base platform- and role-neutral

Priority: P1

Dependencies: R1

Likely files:

- [`modules/home/base.nix`](../../../modules/home/base.nix)
- [`modules/home/desktop.nix`](../../../modules/home/desktop.nix)
- a new terminal or platform helper aspect if useful
- host-role invariants

Steps:

1. Use a terminal-safe pinentry in the shared Linux base. Move GNOME pinentry
   to the desktop aspect where a graphical session is guaranteed.
2. Make Yazi's opener platform-aware: `open` on Darwin and `xdg-open` on Linux.
3. Review fastfetch, btop, GPG agent, clipboard, battery, GPU, and desktop
   assumptions. Keep portable CLI configuration in base and move display-only
   configuration to desktop/Sway/Aerospace aspects.
4. Add evaluated invariants for a headless Linux base and a Darwin base. The
   checks should reject GUI-only dependencies in the headless fixture and
   Linux-only commands in Darwin configuration.
5. Preserve shared shell behavior and avoid duplicating the entire base per
   platform.

Acceptance:

- Soyo does not depend on `pinentry-gnome3`.
- macbook configuration contains no `xdg-open` command.
- Headless, Linux desktop, and Darwin fixtures evaluate with their intended
  packages and programs.
- Shared CLI behavior remains available on every host.

Suggested commit: `refactor(home): keep the shared base platform neutral`

## S1 — Enforce least privilege in GitHub Actions

Priority: P1

Dependencies: B0

Likely files:

- [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml)
- [`.github/workflows/pr-agent.yml`](../../../.github/workflows/pr-agent.yml)
- [`.github/actions/setup-nix/action.yml`](../../../.github/actions/setup-nix/action.yml)
- [`tests/github-workflows/check_workflows.py`](../../../tests/github-workflows/check_workflows.py)
- workflow-policy fixtures
- [`docs/security/supply-chain.md`](../../security/supply-chain.md)

Steps:

1. Pass `CACHIX_AUTH_TOKEN` to the local setup action only on a push to
   `refs/heads/main`. PRs, workflow dispatches, and non-main pushes must use the
   pull-only action path.
2. Keep all third-party actions pinned to immutable full commit SHAs.
3. Reduce PR Agent permissions to the minimum verified by its current
   behavior. Start with `contents: read` and `pull-requests: write`; retain
   `issues: write` only if a tested feature needs it. Remove `contents: write`.
4. Replace the filename-wide “allow any write permission” policy exemption
   with an exact per-workflow permission allowlist.
5. Add rejecting fixtures for a PR job receiving the Cachix token, PR Agent
   receiving `contents: write`, and any newly introduced write scope.
6. Make documentation describe token injection, not merely whether later
   upload commands execute.

Acceptance:

- No PR-context step receives the Cachix auth token.
- PR Agent has no repository-content write permission.
- Workflow policy fails for every permission beyond its exact allowlist.
- Fork PRs and same-repository PRs both take the pull-only cache path.
- `actionlint` and workflow-policy tests pass.

Suggested commit: `fix(ci): restrict cache and review workflow credentials`

## S2 — Make CI and branch protection match the advertised gate

Priority: P1

Dependencies: C4, S1

Likely files:

- [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml)
- [`justfile`](../../../justfile)
- [`docs/testing.md`](../../testing.md)
- [`docs/security/github-settings.md`](../../security/github-settings.md)
- repository settings, only as a separately authorized external action

Steps:

1. Ensure the resilience job builds all KVM-classified checks, including the
   repaired clipboard check.
2. Decide whether planned-host build jobs are mandatory. Because macbook and
   Ubuntu are declared outputs with installation runbooks, make their build
   jobs required once their current platform runners are reliable.
3. Require `Strict KVM behavior tests` in the `main` ruleset now that the
   selected hosted runner and local workflow explicitly support KVM.
4. Update the GitHub settings document with exact current check names.
5. Add a repository-local test comparing the documented/declared KVM check set
   with the checks invoked by CI and `just test-resilience`.
6. Keep the external ruleset mutation separate. Before changing settings,
   inspect current rule IDs and request explicit authorization.

Acceptance:

- Every flake check belongs to exactly one CI evidence tier.
- The KVM list cannot drift among Nix outputs, CI, `just`, and documentation.
- Required-check documentation matches observed repository settings.
- A critical DNS/DHCP, impermanence, backup, or clipboard KVM failure blocks a
  merge after the authorized settings change.

Suggested repository commit: `test(ci): make the complete behavior gate explicit`

## S3 — Add an owned update and vulnerability path for command-code

Priority: P1

Dependencies: R1

Likely files:

- [`modules/_pkgs/command-code.nix`](../../../modules/_pkgs/command-code.nix)
- `modules/_pkgs/command-code-lock/package-lock.json`
- [`renovate.json`](../../../renovate.json)
- [`docs/security/supply-chain.md`](../../security/supply-chain.md)
- a package/update helper under `scripts/` or a `justfile` recipe
- CI security or static checks

Steps:

1. Correct the supply-chain document: the repository does contain a vendored
   npm lockfile and owns its transitive dependency risk.
2. Add a deterministic `just update-command-code` workflow that fetches the
   named upstream tarball, regenerates the lockfile, applies reviewed security
   overrides, and prints the hashes that must be updated. It must not edit
   `flake.lock` or commit automatically.
3. Configure Renovate with an explicit custom manager for the version and
   source URL if it can update this Nix expression safely. Otherwise document
   the intentional manual update cadence and add a freshness check.
4. Add an offline-compatible OSV or equivalent vulnerability scan over the
   vendored lockfile using a pinned Nix package/database strategy. If current
   data requires network access, isolate it in a scheduled security job and do
   not make ordinary evaluation impure.
5. Add a build/smoke check for the wrapped binary and verify that the security
   override is present in the resolved dependency tree.
6. Document who owns exceptions, how long they last, and how a CVE override is
   removed once upstream ships a fixed release.

Acceptance:

- Documentation no longer claims there is no supported lockfile.
- The update process is reproducible from a version change and reviewed hashes.
- The dependency scan examines the vendored npm tree, not only `flake.lock`.
- A fixture vulnerable version or missing override fails the security check.
- `command-code` still builds on every host where R1 enables it.

Suggested commit: `feat(supply-chain): own command-code dependency updates`

## S4 — Scope unfree and insecure package policy to consumers

Priority: P2

Dependencies: S3

Likely files:

- [`lib/mk-nixpkgs-args.nix`](../../../lib/mk-nixpkgs-args.nix)
- host assemblers and package helpers that import it
- package-policy checks
- supply-chain documentation

Steps:

1. Evaluate which host closure, if any, contains `electron-39.8.10` and identify
   the package that requires the exception.
2. Remove the exception if no current closure needs it. Otherwise scope it to
   the single workstation package set and record package, vulnerability,
   rationale, owner, and expiry/review date.
3. Replace global `allowUnfree = true` with a reviewed
   `allowUnfreePredicate` where practical. Keep the package overlay available
   only to hosts that consume it after R1.
4. Add a check that rejects new insecure allowances without structured
   rationale and an expiry date.

Acceptance:

- Soyo has no unrelated insecure-package allowance.
- Every unfree/insecure exception corresponds to an evaluated consumer.
- Stale exceptions fail a check or are removed.
- Workstation closures still build.

Suggested commit: `refactor(nixpkgs): scope package policy exceptions`

## H1 — Make the macbook configuration and runbook agree

Priority: P2

Dependencies: C3, R2

Likely files:

- [`modules/home/aerospace.nix`](../../../modules/home/aerospace.nix)
- [`modules/home/desktop.nix`](../../../modules/home/desktop.nix)
- a shared terminal aspect if introduced by R2
- [`modules/parts/macbook.nix`](../../../modules/parts/macbook.nix)
- [`docs/install-macbook.md`](../../install-macbook.md)
- [`docs/workstation-setup.md`](../../workstation-setup.md)
- [`hosts/macbook/INSTALL.md`](../../../hosts/macbook/INSTALL.md)

Steps:

1. Establish one terminal contract. Prefer a shared Ghostty aspect if the
   locked package and Home Manager module support aarch64-darwin; otherwise
   choose an installed Darwin terminal and document it.
2. Bind Aerospace `Cmd+Return` to that installed terminal, not `kitty` unless
   kitty is deliberately added and documented.
3. Generate an evaluated package/capability inventory for macbook. Reconcile
   Firefox, Bitwarden, Signal, Obsidian, Ghostty, and other matrix claims with
   packages actually available on Darwin. Document operator-installed apps
   explicitly instead of marking them declarative.
4. Correct the shell check: nix-darwin enables/configures zsh but the current
   user declaration does not make `/run/current-system/sw/bin/zsh` the login
   shell. Either configure the login shell deliberately with a verified
   nix-darwin option or expect `/bin/zsh` and test managed shell behavior
   separately.
5. Keep agenix setup visibly blocked until real hardware keys exist. Do not
   create placeholder ciphertext or public keys.
6. Add pure checks for terminal command availability and documented package
   claims. Retain actual launch, login-shell, and keyboard validation for the
   first hardware deployment.

Acceptance:

- Every Aerospace executable binding resolves to an installed package or a
  macOS system executable.
- Package matrix claims match the evaluated Darwin configuration.
- The install guide's shell expectation matches the configured login shell.
- The macOS CI closure build remains green.

Suggested commit: `fix(macbook): align desktop bindings and install contract`

## H2 — Rewrite the Ubuntu standalone Home Manager contract

Priority: P2

Dependencies: C3, R1, R2

Likely files:

- [`modules/parts/ubuntu.nix`](../../../modules/parts/ubuntu.nix)
- [`docs/install-ubuntu.md`](../../install-ubuntu.md)
- [`docs/workstation-setup.md`](../../workstation-setup.md)
- standalone Home Manager evaluation checks

Steps:

1. Remove the agenix host-key, `secrets/ubuntu.pub`, and rekeyed-directory
   instructions unless standalone Home Manager is first given a complete,
   justified secret activation design. The current plan should use no Ubuntu
   host ciphertext.
2. State clearly that Home Manager installs/configures zsh but does not change
   Ubuntu's login shell. Provide the explicit `chsh` or OS-administrator step
   only after verifying the path Ubuntu accepts in `/etc/shells`.
3. Define how Sway is started on Ubuntu. If the display manager cannot discover
   a user-profile Wayland session, document a supported OS-level session entry
   or a console `dbus-run-session sway` path instead of promising automatic
   availability.
4. Separate Nix-managed prerequisites from apt/system administrator
   prerequisites such as graphics, portals, PAM, and display-manager setup.
5. Add a standalone HM evaluation/build check for expected packages and files.
   Keep real display-manager and login-shell validation manual until an Ubuntu
   VM fixture or target machine exists.

Acceptance:

- The guide contains no unused agenix enrollment steps.
- Shell and Sway claims distinguish user configuration from OS configuration.
- A clean Ubuntu operator can follow the prerequisites without inventing a
  missing host secret or session registration step.
- The Ubuntu activation package builds in CI.

Suggested commit: `docs(ubuntu): correct the standalone home manager runbook`

## M1 — Remove host-specific values from reusable service aspects

Priority: P2

Dependencies: C2

Likely files:

- [`modules/nixos/backup.nix`](../../../modules/nixos/backup.nix)
- [`modules/nixos/observability.nix`](../../../modules/nixos/observability.nix)
- [`hosts/soyo/backup.nix`](../../../hosts/soyo/backup.nix)
- [`hosts/soyo/observability.nix`](../../../hosts/soyo/observability.nix)
- backup and observability integration checks

Steps:

1. Replace the hardcoded backup SSH user/host command with typed options or a
   structured SFTP target. Keep the repository URL, SSH identity, host-key
   policy, and persisted known-hosts path explicit.
2. Move `czworaczki.home.arpa`, `${hostName}-backup`, and Soyo-specific values
   into `hosts/soyo/backup.nix`.
3. Add an observability LAN-interface option and move `enp1s0` into host data.
   Use it for neighbor discovery and firewall rules.
4. Either honor `grafana.listenAddress` in the Grafana service configuration
   and firewall policy or remove the misleading option. Prefer honoring it
   with an IP/address type appropriate to the upstream option.
5. Add alternate-host fixtures proving the aspects evaluate without Soyo's
   hostname, NIC, or NAS target.

Acceptance:

- Reusable modules contain no `czworaczki`, `enp1s0`, or implicit Soyo backup
  user construction.
- `grafana.listenAddress` changes the evaluated listener or no longer exists.
- Soyo's generated service behavior remains unchanged apart from intentional
  fixes.
- Backup and observability integration checks pass for Soyo and a fixture host.

Suggested commit: `refactor(services): move appliance data into host options`

## D1 — Reconcile documentation lifecycle and current claims

Priority: P2

Dependencies: C1 through M1 as applicable

Likely files:

- [`docs/learning/project-assessment.md`](../../learning/project-assessment.md)
- [`docs/superpowers/specs/repository-gaps-and-improvements.md`](../specs/repository-gaps-and-improvements.md)
- [`docs/status.json`](../../status.json)
- [`docs/README.md`](../../README.md)
- canonical and subsystem documentation touched by earlier tasks

Steps:

1. Re-audit every claim in the earlier project assessment and gaps plan against
   evaluated outputs and completed checks.
2. Replace unqualified five-star/current-state claims with dated evidence and
   residual risks, including the failures repaired by this plan.
3. Verify that lifecycle metadata and document headers continue to present this
   file as the sole active implementation plan. Mark newly completed work and
   obsolete evidence `completed`, `superseded`, or `historical`, with replacement
   links where appropriate.
4. Keep architecture decisions in specs, execution steps in plans, operational
   commands in runbooks, and dated evidence in historical assessments.
5. Record IPv6, RAID1, offsite replication, guest applications, and appliance
   redundancy as intentional deferrals/accepted risks.
6. Remove duplicate or contradictory KVM-count, host-status, package-matrix,
   cache-token, and required-check claims.
7. Run the documentation correctness checker after each lifecycle change.

Acceptance:

- Every active/canonical document is linked from `docs/README.md`.
- This remains the only active implementation plan; predecessor task lists are
  visibly frozen and link to this replacement.
- No current plan describes already completed work as missing.
- Current status claims have a date or a reproducible evidence source.
- Intentional deferrals are not listed as unexplained defects.
- Links, anchors, lifecycle status, and discoverability checks pass.

Suggested commit: `docs(status): reconcile active plans with repository state`

## D2 — Make developer workflow names and descriptions truthful

Priority: P2

Dependencies: C4, S2, D1

Likely files:

- [`justfile`](../../../justfile)
- [`modules/parts/perSystem.nix`](../../../modules/parts/perSystem.nix)
- [`docs/testing.md`](../../testing.md)
- [`AGENTS.md`](../../../AGENTS.md) if its workflow wording changes

Steps:

1. Decide whether `just fmt` should format only Nix or whether treefmt should
   also enable supported Python, shell, and Markdown formatters. Prefer adding
   formatters only if they do not conflict with existing lint-only policy;
   otherwise correct the recipe description.
2. Rename or rewrite `just check` documentation so it does not claim that
   `nix flake check` builds every host output. Keep explicit host closure recipes
   and CI jobs visible.
3. Remove the duplicate `formatting`/`treefmt` derivation unless separate names
   serve a documented consumer.
4. Ensure `just test-resilience`, CI, and testing docs use the complete KVM set
   established by C4/S2.
5. Add lightweight contract tests for recipe presence and documented command
   mappings where existing script-contract infrastructure supports them.

Acceptance:

- Every `just --list` description matches the command's actual scope.
- Formatting and linting are clearly distinguished.
- No documentation claims `nix flake check` builds host closures unless a
  wrapper actually does so.
- Duplicate check aliases are removed or justified.

Suggested commit: `docs(workflow): align just recipes with actual gates`

## G1 — Run the complete repository gate

Priority: P0 for final integration

Dependencies: all repository-local work items

Run in this order:

```bash
git diff --check
just fmt
just lint
nix flake check path:. --no-build --show-trace
nix build --no-link --keep-going \
  path:.#nixosConfigurations.soyo.config.system.build.toplevel \
  path:.#nixosConfigurations.zbook.config.system.build.toplevel \
  path:.#homeConfigurations.ubuntu.activationPackage
just test-resilience
just check
```

On macOS CI, also build:

```bash
nix build --no-link --keep-going \
  path:.#darwinConfigurations.macbook.config.system.build.toplevel
```

Additional acceptance:

- No Home Manager/Nixpkgs mismatch warning remains.
- No check passes solely because the broken pre-fix derivation is cached.
- `git status --short` contains only intended source, documentation, and the
  command-generated `flake.lock` changes.
- Gitleaks reports no plaintext credentials.
- Every mutation fixture fails the intended production invariant.

## G2 — Separately authorized live validation

Priority: P1 after deployment

Dependencies: G1 and explicit user authorization

These checks cannot be claimed by repository builds:

1. deploy with `just deploy <host>` using the normal rollback-capable path;
2. run `just healthcheck soyo appliance enp1s0` and `just healthcheck zbook`;
3. on a fresh/unregistered fixture or approved host, confirm Tailscale first
   authentication waits for and succeeds after `tailscaled` starts;
4. force a harmless fixture unit failure and verify ntfy delivery;
5. run the documented smartd warning fixture without faking a real disk fault;
6. confirm Grafana's Btrfs rule evaluates with real textfile metrics;
7. inspect the retained Limine generation count after subsequent rebuilds;
8. perform the documented restic restore drill to a scratch location;
9. on first macbook/Ubuntu hardware, verify login shell, terminal shortcut,
   desktop session, and documented application matrix;
10. change GitHub required checks only after reviewing current ruleset state and
    receiving explicit authorization.

Reboot, TPM enrollment, passphrase fallback, initrd SSH, direct-link rescue,
DHCP-client behavior, destructive restore, and disk-failure simulation remain
the manual safety boundary defined by `AGENTS.md` and the canonical design.

## Suggested PR sequence

1. `fix(tailscale): order authentication after tailscaled` — C1.
2. `fix(observability): share the btrfs alert metric contract` — C2.
3. `fix(flake): align home manager inputs with host channels` — C3.
4. `fix(test): make primary clipboard coverage deterministic` — C4.
5. `feat(maintenance): complete operational failure alerts` — O1.
6. `fix(boot): bound retained limine generations` — O2.
7. `feat(healthcheck): verify backup freshness and every probe` — O3.
8. `refactor(home): isolate development tools and credentials` — R1.
9. `refactor(home): keep the shared base platform neutral` — R2.
10. `fix(ci): restrict cache and review workflow credentials` — S1.
11. `test(ci): make the complete behavior gate explicit` — S2. Apply the
    corresponding GitHub ruleset change only as a separately authorized
    operation after this repository PR is green.
12. `feat(supply-chain): own command-code dependency updates` — S3.
13. `refactor(nixpkgs): scope package policy exceptions` — S4.
14. `fix(macbook): align desktop bindings and install contract` — H1.
15. `docs(ubuntu): correct the standalone home manager runbook` — H2.
16. `refactor(services): move appliance data into host options` — M1.
17. `docs(status): reconcile active plans with repository state` — D1.
18. `docs(workflow): align just recipes with actual gates` — D2.

Each PR must be independently buildable and revertible. If a task exposes a
new production defect, add it to this plan with evidence and dependencies
before expanding that PR's scope.
