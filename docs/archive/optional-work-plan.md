# Optional Work Plan

> **Status: Superseded.** Completed results remain useful history. Outstanding
> resilience work moved to the
> [current remediation plan](../superpowers/plans/2026-07-23-repository-assessment-remediation.md).

<!-- markdownlint-configure-file {"MD024": {"siblings_only": true}} -->

This plan covers work intentionally left after the repository gap pass. It is
written for one bounded task per agent. Do not execute several tasks in one
thread, and do not let an implementation task implicitly authorize deployment,
SSH access, rebooting, TPM changes, or destructive recovery drills.

The canonical constraints are in `AGENTS.md` and
`docs/superpowers/specs/soyo-dns-dhcp-appliance.md`. Read both before editing.

Model and effort labels describe the recommended session configuration. The
current subagent interface cannot select either value itself, so the
orchestrator must still keep every assignment bounded to one task and apply the
listed review gates.

## Global rules for every agent

1. Inspect the working tree before editing and preserve unrelated changes.
2. Never edit `flake.lock` by hand, `secrets/rekeyed/`, encrypted `.age` files,
   or `hosts/*/facter.json`.
3. Use `apply_patch` for source edits.
4. Keep DNS and DHCP as Soyo's only critical roles. Tests must not add a guest
   service to the production configuration.
5. Prefer structured NixOS options over assertions against rendered text.
6. Do not contact a live host unless the user explicitly authorizes that task.
7. Do not deploy, reboot, modify a TPM slot, enroll keys, force a unit failure,
   or perform a restore drill without separate explicit authorization.
8. After implementation, run the task's acceptance commands, `git diff --check`,
   and inspect the complete diff.
9. Do not commit unless explicitly asked. If asked, use a Conventional Commit
   message without a period.

## Execution order

```text
O0 green baseline (complete)
 |
 +--> O1 DNS/DHCP VM test
 |
 +--> O2 role-boundary assertions
 |
 +--> O3 topology determinism --> O4 topology freshness
 |
 +--> O5 health-check testability
                         |
                         +--> O6 authorized deploy and live checks
                                      |
                                      +--> O7 authorized manual drills
```

O1, O2, O3, and O5 may run independently after O0. O4 depends on O3. O6 should
wait until all desired repository changes pass O0 again. O7 is an operator-led
runbook, not autonomous agent work.

## O0 — Reproducible green baseline (completed)

- Status: Completed during the gap-remediation pass
- Priority: Blocking prerequisite
- Model: `gpt-5.6-terra`
- Effort: High
- Authorization: Repository-local only

### Outcome

The exact complete validation command now passes from a normal dirty or clean
checkout without relying on `.git/hooks/pre-commit`. A successful `--no-build`
evaluation was not accepted as sufficient.

`modules/parts/perSystem.nix` now gives both treefmt checks a
`pkgs.lib.cleanSource inputs.self` source. This removes VCS metadata from the
formatting sandbox while retaining repository files, including untracked work
when invoked through `path:.`. The user's Git hook was left unchanged.

### Inspect first

- `flake.nix`
- `modules/parts/perSystem.nix`
- `.gitignore`
- `.github/workflows/ci.yml`
- `justfile`
- the derivations for `checks.x86_64-linux.formatting` and
  `checks.x86_64-linux.pre-commit`

### Likely files touched

- `modules/parts/perSystem.nix`
- possibly `flake.nix`, `.gitignore`, `justfile`, or CI if the canonical command
  changes
- documentation only if a non-obvious source-input decision needs explanation

### Completed method

1. Reproduced the failure with `nix flake check path:. --keep-going`.
2. Identified treefmt's `inputs.self` source as including `.git` under `path:`
   semantics.
3. Filtered both treefmt check inputs with `cleanSource`.
4. Restored and preserved the user's existing Git hook unchanged.
5. Re-ran the complete path-based flake check successfully.

### Non-goals

- No flake input updates.
- No disabling treefmt, pre-commit, or any hook.
- No exclusion of legitimate tracked files merely to make checks green.
- No live-host checks.

### Recorded acceptance criteria

Run all of the following successfully:

```bash
nix build path:.#checks.x86_64-linux.pre-commit --no-link
nix build path:.#checks.x86_64-linux.formatting --no-link
nix flake check path:. --keep-going
nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose
git diff --check
```

Also build both complete host closures if the full flake check does not do so:

```bash
nix build path:.#nixosConfigurations.soyo.config.system.build.toplevel --no-link
nix build path:.#nixosConfigurations.zbook.config.system.build.toplevel --no-link
```

### Risk and rollback

Source filtering can accidentally omit files from checks. Review the resulting
source file list and revert only this task's edits if coverage shrinks. Never
use destructive Git commands to roll back a shared working tree.

Suggested commit: `fix(checks): isolate validation from git metadata`

## O1 — Add a packet-level DNS/DHCP NixOS VM test

- Status: Completed
- Priority: High
- Model: `gpt-5.6-sol`
- Effort: Extra-high
- Depends on: O0
- Authorization: Repository-local only

### Objective

Complement `modules/parts/dns-dhcp-checks.nix` with a narrow NixOS integration
test proving that Blocky and dnsmasq start together and exchange real DNS
traffic on an isolated virtual LAN.

### Inspect first

- `modules/parts/dns-dhcp-checks.nix`
- `modules/nixos/blocky.nix`
- `modules/nixos/dhcp.nix`
- `hosts/soyo/dns.nix`
- `hosts/soyo/dhcp.nix`
- `hosts/soyo/network-policy.nix`
- `hosts/soyo/reservations.nix`
- current nixpkgs NixOS test examples for multiple nodes and dnsmasq

### Likely files touched

- new `modules/parts/dns-dhcp-vm-check.nix`
- optionally a small reusable fixture under `lib/network/`
- a short learning comment or documentation note if a new NixOS test idiom is
  introduced

Because `modules/` is auto-imported, the new file must be a valid flake-parts
module. Plain helpers belong under `lib/`.

### Required test shape

Use a server node and a LAN client node. Reuse production aspect modules and
network data where practical, but do not import the complete Soyo host: its
disk, TPM, Secure Boot, hardware facts, impermanence rollback, and remote unlock
are outside this test.

At minimum prove:

- Blocky and dnsmasq both become active without a port conflict.
- A client can resolve `soyo.home.arpa` through Blocky.
- A reservation-backed hostname resolves to its expected address.
- a PTR request for a known LAN address is delegated from Blocky to dnsmasq;
- an external name resolves through a deterministic test-local upstream, not
  the public internet;
- the configured blocked-domain behavior is exercised without downloading a
  remote block list;
- dnsmasq uses the configured lease path and survives a service restart.

If DHCP lease acquisition is added, keep it as a separate assertion after DNS
is stable. The test must not depend on external networking or wall-clock DNS.

### Non-goals

- No TPM, Secure Boot, disk, initrd SSH, Tailscale, observability, or restic.
- No public DNS or remote block-list access.
- No change to production port ownership.
- No live Soyo access.

### Acceptance criteria

```bash
nix build path:.#checks.x86_64-linux.dns-dhcp-vm --no-link -L
nix flake check path:. --keep-going
git diff --check
```

The check must run in CI through `nix flake check`; do not add an unrelated
second CI implementation unless runner resource evidence requires it.

### Risk and rollback

The main risks are a test that accidentally uses the network, tests rendered
implementation details, or imports too much of Soyo. A narrow fixture is
preferable to weakening production modules. If resource use is too high,
measure it and split the VM check into a dedicated CI job only after the user
accepts that tradeoff.

Suggested commit: `test(soyo): add DNS and DHCP integration VM`

## O2 — Add host role-boundary assertions

- Status: Completed
- Priority: Medium-high
- Model: `gpt-5.6-terra`
- Effort: High
- Depends on: O0
- Authorization: Repository-local only

### Objective

Turn remaining host-role invariants into explicit evaluation checks without
using brittle source-code grep tests.

### Inspect first

- `modules/parts/soyo.nix`
- `modules/parts/zbook.nix`
- `modules/nixos/base.nix`
- `modules/home/base.nix`
- `modules/nixos/server.nix`
- `modules/nixos/workstation.nix`
- `modules/nixos/remote-unlock.nix`
- `modules/parts/aspect-options.nix`
- existing focused checks under `modules/parts/`

### Likely files touched

- new `modules/parts/host-role-invariants.nix`
- an existing role module only if evaluation exposes a real violation

### Required assertions

At minimum verify evaluated configurations enforce these contracts:

- zbook does not enable dnsmasq, Blocky, DHCP server behavior, or server-only
  remote unlock;
- Soyo does not enable NetworkManager or graphical desktop/display-manager
  behavior;
- both hosts expose the expected declarative `/etc/nix-config/role` marker;
- role markers agree with the assembler's enabled role;
- server-specific networking and workstation GUI behavior do not leak into the
  opposite host;
- base modules remain reusable without choosing NetworkManager, systemd-networkd,
  swap policy, or GUI/display behavior.

For the last item, prefer evaluating a minimal fixture importing the base aspect
over text matching. If a minimal fixture is disproportionately complex, document
the limitation and test only stable evaluated contracts.

### Non-goals

- No broad aspect-framework refactor.
- No renaming public options solely for the test.
- No attempt to infer roles heuristically from arbitrary systemd units.

### Acceptance criteria

```bash
nix build path:.#checks.x86_64-linux.host-role-invariants --no-link
nix flake check path:. --keep-going
git diff --check
```

Temporarily demonstrate locally that one assertion fails when a forbidden role
is enabled, then restore the file before final verification. Do not leave the
intentional failure in the working tree.

### Risk and rollback

Over-specific assertions can lock in implementation details. Assert role
behavior, not incidental package lists or generated unit names. Revert only the
new check if it cannot distinguish behavior from implementation safely.

Suggested commit: `test(hosts): enforce role boundaries`

## O3 — Prove topology rendering is deterministic

- Status: Completed; byte-for-byte determinism proven
- Priority: Medium
- Model: `gpt-5.6-luna`
- Effort: Medium
- Depends on: O0
- Authorization: Repository-local only

### Objective

Determine whether two topology builds from identical source produce byte-for-byte
identical `main.svg` and `network.svg`. Do not add a freshness gate until this
is proven.

### Inspect first

- `modules/parts/topology.nix`
- `hosts/soyo/topology.nix`
- `hosts/zbook/topology.nix`
- `docs/topology/main.svg`
- `docs/topology/network.svg`
- topology CI job in `.github/workflows/ci.yml`

### Likely files touched

- none for the investigation;
- `docs/optional-work-plan.md` or a focused topology note only if the result
  needs recording;
- `modules/parts/topology.nix` only for a small deterministic-output fix with a
  clearly identified cause

### Method and acceptance criteria

Build twice with separate output links or copy outputs into separate temporary
directories, then compare hashes and contents:

```bash
nix build path:.#topology --no-link --print-out-paths
```

Force a rebuild only through a safe Nix method; do not delete arbitrary store
paths. Record whether both SVGs are identical and inspect any differing fields.

O3 passes when either:

- reproducibility is demonstrated; or
- nondeterministic fields are precisely identified and a bounded follow-up is
  documented.

Always finish with:

```bash
nix flake check path:. --keep-going
git diff --check
```

### Non-goals

- No manual normalization that hides meaningful diagram changes.
- No committed generated SVG updates during the investigation.
- No freshness gate if output remains nondeterministic.

### Risk and rollback

Low risk if read-only. If changing rendering configuration, ensure labels,
addresses, and connections remain intact and revert the task if the diagram
loses information.

Suggested commit if needed: `fix(topology): make diagram output deterministic`

## O4 — Enforce committed topology freshness

- Status: Completed
- Priority: Medium
- Model: `gpt-5.6-luna`
- Effort: Medium
- Depends on: O3 proving deterministic output
- Authorization: Repository-local only

### Objective

Fail validation when `docs/topology/main.svg` or `network.svg` differs from the
declaratively generated topology.

### Likely files touched

- `modules/parts/topology.nix` or a new `modules/parts/topology-checks.nix`
- `.github/workflows/ci.yml`
- `justfile` if it exposes a documented refresh command
- `docs/topology/*.svg` only by copying exact generated output
- `README.md` or a topology documentation note for the refresh workflow

### Required behavior

- Add a `checks.topology-freshness` derivation comparing generated and committed
  SVGs byte-for-byte.
- Print the stale filename and an exact refresh command on failure.
- Keep the topology artifact upload if it remains useful, but avoid building
  the same expensive output twice in CI without reason.
- Ensure the source filter used by O0 includes committed topology SVGs.

### Non-goals

- No snapshot tooling outside Nix.
- No automatic CI commit or push.
- No ignoring semantic differences with a permissive normalization pass.

### Acceptance criteria

```bash
nix build path:.#checks.x86_64-linux.topology-freshness --no-link
nix flake check path:. --keep-going
git diff --check
```

Temporarily alter a copy of one committed SVG and show that the focused check
fails; restore it before final verification.

### Risk and rollback

Large generated diffs can obscure review. Confirm determinism and visually
inspect both diagrams after any refresh. Revert the freshness check if it flakes
between identical builds.

Suggested commit: `test(topology): detect stale diagrams`

## O5 — Make live health checks locally testable

- Status: Completed
- Priority: Medium
- Model: `gpt-5.6-terra`
- Effort: High
- Depends on: O0
- Authorization: Repository-local only

### Objective

Add automated tests for health-check argument parsing, role selection, and
command construction without making SSH connections. This reduces the chance
that O6 discovers a scripting bug only after deployment.

### Inspect first

- `scripts/healthcheck.sh`
- `modules/parts/perSystem.nix`
- host role marker definitions in server/workstation modules
- existing shellcheck and test conventions

### Likely files touched

- `scripts/healthcheck.sh`
- new test script under `scripts/tests/` or a test fixture outside `modules/`
- `modules/parts/perSystem.nix` to expose a flake check

### Required behavior

Use command stubs or an explicit test mode so tests can prove:

- explicit host, role, and NIC arguments override discovery;
- the declarative role marker is preferred;
- the legacy Tailscale fallback is used only when the marker is absent;
- an invalid role exits with status 2;
- workstation checks do not invoke appliance-only DNS/DHCP commands;
- appliance checks do invoke critical service and DNS assertions;
- failure count becomes the exit status without aborting on the first failure.

Do not weaken SSH host-key or authentication behavior for production runs.

### Non-goals

- No real SSH, DNS, sudo, or Tailscale access in the repository test.
- No general-purpose shell testing framework unless already available and
  justified by more than this script.

### Acceptance criteria

```bash
nix build path:.#checks.x86_64-linux.healthcheck-tests --no-link -L
nix flake check path:. --keep-going
nix develop path:. -c shellcheck scripts/healthcheck.sh
git diff --check
```

### Risk and rollback

Refactoring shell for testability can change quoting or SSH argument semantics.
Keep production commands visible and run ShellCheck. Revert the refactor if the
test seam makes the operational script harder to audit.

Suggested commit: `test(healthcheck): cover role and argument handling`

## O6 — Deploy and run live non-destructive verification

- Status: Pending explicit deployment and SSH authorization
- Priority: Operational
- Model: `gpt-5.6-sol`
- Effort: High
- Depends on: all selected repository tasks and a fresh successful O0
- Authorization: Explicit user approval required for deploy and SSH

### Objective

Deploy an already-reviewed revision, then run non-destructive health checks on
Soyo and zbook. This task changes live systems and must not start from the plan
alone.

### Pre-deployment gate

Before requesting authorization, report:

- the exact commit or dirty-tree state to deploy;
- all successful repository checks;
- closure diffs for both hosts;
- whether boot, networking, DNS/DHCP, persistence, secrets, NVIDIA, or service
  units changed;
- a rollback command and expected magic-rollback behavior.

### Authorized commands

Only after explicit approval, use the repository's documented deploy commands:

```bash
nix develop '.#' -c deploy .#soyo
nix develop '.#' -c deploy .#zbook
nix run .#healthcheck -- soyo
nix run .#healthcheck -- zbook
```

Deploy hosts separately. Verify Soyo before proceeding to zbook. A failure on
one host stops the sequence; do not improvise a reboot or rollback outside the
documented deploy-rs behavior without user direction.

### Acceptance criteria

- Deploy-rs reports success for each authorized host.
- Every automated health-check line reports `[PASS]`.
- DNS forward, blocked-domain, local A, and reverse PTR checks pass on Soyo.
- The exact deployed system generation and any warnings are recorded.
- No manual/destructive drill is silently counted as complete.

### Non-goals and risk

This task does not authorize reboot, TPM enrollment changes, secret rekeying,
forced failures, restore operations, or physical rescue testing. Soyo is a LAN
critical appliance; schedule deployment when a brief DNS/DHCP interruption is
acceptable and retain a local-console path.

No repository commit is inherent to this task.

## O7 — Operator-led manual resilience drills

- Status: Pending drill-by-drill operator authorization
- Priority: Operational
- Model: `gpt-5.6-sol` as a read-only guide and recorder
- Effort: Extra-high
- Depends on: O6 and explicit drill-by-drill approval
- Authorization: Physical/operator approval required for every subsection

### Objective

Verify properties that automated checks cannot prove. The agent prepares an
exact checklist, validates prerequisites, and records evidence. The operator
performs physical or destructive actions.

### Split into separate sessions

Never combine these into one autonomous run:

1. Normal reboot and TPM auto-unlock.
2. LAN initrd SSH unlock on port 2222.
3. Direct-link rescue with the documented static addresses.
4. DHCP client receives the intended DNS server and `home.arpa` search domain.
5. Forced non-critical unit failure sends the ntfy notification.
6. Restic restore drill into a temporary destination with content verification.
7. Tampered boot artifact fails checksum verification.
8. Break-glass passphrase unlock after deliberate TPM-slot disruption.
9. TPM re-enrollment restores PCR `0+2+7` auto-unlock.

### Required references

- `docs/recovery.md`
- `docs/backup-and-restore.md`
- `docs/install-soyo.md`
- `docs/update-and-rollback.md`
- canonical appliance design

### Safety gates

For each drill, the agent must state:

- whether it is destructive;
- required physical presence and expected outage;
- verified fallback key/passphrase and local-console access;
- exact success and abort conditions;
- recovery steps if the primary path fails;
- what evidence to record without exposing secrets.

The agent must not request or print a passphrase, private key, recovery secret,
or decrypted secret content. Never bind PCR 8 or PCR 9. Always preserve the
passphrase keyslot.

### Acceptance criteria

Each drill has a dated operator record containing the generation tested, result,
evidence summary, and follow-up issue if it failed. A skipped drill remains
explicitly `not verified`; it is never inferred from a passing health check.

### Risk and rollback

Several drills can make Soyo unavailable and require physical recovery. Stop at
the first unexpected result. Do not proceed to TPM re-enrollment, keyslot
changes, tampering, or restoration based only on this plan; use the canonical
runbook and obtain fresh explicit authorization.

## Final review task

- Model: `gpt-5.6-sol`
- Effort: Extra-high
- Authorization: Read-only repository review

After O1 through O5, use a fresh agent to review the combined diff without
editing first. The reviewer should look for:

- production behavior changed merely to satisfy a test;
- VM tests using external network access;
- duplicated network policy rather than reuse of validated data;
- new helpers accidentally placed under the auto-imported `modules/` tree;
- checks omitted from `nix flake check` or CI;
- role assertions tied to incidental implementation details;
- nondeterministic topology comparisons;
- weakened health-check SSH or sudo behavior;
- changes to boundary files or secret material.

The final repository gate is:

```bash
nix flake check path:. --keep-going
nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose
git diff --check
```

Both host closures must also build, and all focused checks added by this plan
must pass. Only then should O6 deployment authorization be requested.
