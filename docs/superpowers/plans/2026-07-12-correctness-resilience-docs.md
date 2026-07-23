# Correctness, Resilience, and Documentation Execution Plan

Date: 2026-07-12

Status: superseded on 2026-07-22 by the
[Repository Assessment Remediation Plan](2026-07-23-repository-assessment-remediation.md)

This file is a frozen planning record. Its completed work remains useful
historical context, but its remaining task list is no longer authoritative.
Revalidate any apparently unfinished item and map it into the replacement plan
before implementation.

## Goal

Raise this public, multi-host NixOS flake from a strong declarative setup to a
repository whose critical behavior is exercised under failure, whose scripts
are packaged and tested idiomatically, whose CI has a smaller supply-chain
attack surface, and whose documentation is attractive without exposing more
home-network detail than necessary.

This plan is designed for one bounded task per subagent. Agents must read
`AGENTS.md` and the canonical appliance specification before acting, preserve
unrelated working-tree changes, and never deploy, reboot, rekey, restore, or
modify generated secrets/hardware inventories without explicit authorization.

## Current evidence and remaining work

The repository already has substantially more verification than the original
gap report described:

- `nix flake check path:. --keep-going` is the local whole-repository gate.
- `dns-dhcp-vm-check.nix` performs a real two-node DNS/DHCP exchange, forward
  and reverse lookup, blocking, lease creation, and dnsmasq restart continuity.
- Pure evaluation checks cover reservation validation, generated DNS/DHCP
  configuration, host role boundaries, guest resource isolation, persistence,
  backup ownership, and topology freshness.
- `healthcheck_test.sh` exercises the live-check command with hermetic command
  doubles.
- topology output is deterministic and checked byte-for-byte.
- CI builds both host closures and publishes topology artifacts.

The remaining gaps are deeper failure semantics and maintainability:

- DNS/DHCP tests prove the happy path and one restart, but not upstream
  failure, guest resource pressure, invalid packets, recovery, or critical-role
  isolation under chaos.
- persistence checks inspect configuration but do not boot, mutate state,
  reboot, and prove that only declared state survives.
- backup checks inspect wiring but do not create, check, restore, compare, or
  corrupt a repository in an isolated test.
- initrd recovery is configuration-checked but its dependency graph and boot
  artifacts are not tested as a coherent recovery interface.
- several systemd shell fragments use `writeShellScript`; strict shell checking
  and service hardening are not yet a uniform repository policy.
- scripts are partly packaged, but two operational scripts are run ad hoc and
  the health-check test harness is custom shell rather than a named test suite.
- CI actions use mutable major-version tags, and lint/evaluation/build work is
  duplicated across jobs.
- the 218-line README is a detailed inventory rather than a welcoming entry
  point; there is no `docs/README.md` navigation hub or automated internal-link
  and orphan check.
- old implementation plans remain useful history but can be mistaken for
  current instructions. `hosts/zbook/INSTALL.md` also contains historical
  COSMIC text that conflicts with the active Sway/DMS desktop.

## GitHub issue #2 reconciliation

Authenticated read-only GitHub access works now. Every GitHub-aware agent must
still begin with:

```bash
gh auth status
gh repo view knirski/nix-config --json nameWithOwner,isPrivate,url,defaultBranchRef
```

The repository is public. Its only open issue is
[#2, “Bootstrap Soyo from NixOS Live USB”](https://github.com/knirski/nix-config/issues/2).
The issue is an early bootstrap checklist from 2026-06-28. It contains exact
disk identity, interface name, LAN address, DHCP/DNS ports, and a
branch-specific install command. Most of it is superseded by
`docs/install-soyo.md`, the current secrets flow, Secure Boot completion, and
the current health check.

Do not close it on assumption. Task D4 must compare every still-valid safety
gate against the canonical runbook, move any missing knowledge, add a final
comment linking the replacement, and only then close it. Closing an issue is an
external mutation and therefore requires the user's explicit approval at
execution time.

## Public topology threat model

The current detailed SVG files are already committed to a public repository:
`main.svg` is 1,680,667 bytes and `network.svg` is 764,093 bytes at this audit.
They expose more than RFC 1918 addresses: recognizable device names, hostnames,
MAC addresses, interface names, service layout, backup destinations, local
paths, and recovery-network structure may appear in generated text. Private IP
and MAC addresses are not credentials, but the collection is useful
reconnaissance and can reveal inventory and trust relationships.

Embedding those same SVGs in the README does not newly publish them, but it
increases prominence, indexing, casual discovery, and the chance that forks or
social previews preserve them. A shorter README does not remedy their existing
publication or remove prior Git history. This plan chooses to stop committing
future detailed outputs and retain operator-detailed builds locally. D1 records
that decision and removes future publication paths while acknowledging the
existing public commits. Sanitizing detailed source instead is a later design
change; history rewriting is separate and disruptive. The README default is
therefore:

1. generate a sanitized README overview containing only roles and trust/data
   flows, with labels such as “LAN,” “VPN,” “backup target,” and “upstream DNS”;
2. omit exact IPs, MACs, interface names, personal device names, disk IDs,
   usernames, repository paths, and rescue addresses;
3. link to reviewed documentation for architecture details;
4. enforce the selected D1 policy: stop publishing future detailed outputs,
   while acknowledging that existing commits remain public. Do not rewrite Git
   history as part of this plan.

The README may embed a sanitized SVG via a relative Markdown image only after
its generated source, allowed-vocabulary, structure, size, and active-content
tests pass. This lowers disclosure risk; it is not an unconditional claim that
an SVG is “safe.” Keep generation local and deterministic; reject scripts,
event handlers, foreign objects, external URLs/resources, and unexpected links.

## Primary references and researched patterns

The following are implementation inputs, not cargo-cult requirements:

- The current NixOS manual documents `pkgs.testers.runNixOSTest` and the Python
  test-driver API in
  [Writing NixOS tests](https://github.com/NixOS/nixpkgs/blob/052c7170b6616f049d374388d3a3a183b404400e/nixos/doc/manual/development/writing-nixos-tests.section.md).
- Current nixpkgs exposes derivation assertions such as `testEqualContents` and
  the exported `testBuildFailure'` helper (implemented under
  `testBuildFailurePrime`), documented in the
  [tester documentation](https://github.com/NixOS/nixpkgs/blob/052c7170b6616f049d374388d3a3a183b404400e/doc/build-helpers/testers.chapter.md).
- NixOS systemd units expose `enableStrictShellChecks`; its current option and
  semantics are in
  [systemd-unit-options.nix](https://github.com/NixOS/nixpkgs/blob/052c7170b6616f049d374388d3a3a183b404400e/nixos/lib/systemd-unit-options.nix).
- nixpkgs' `writeShellApplication` supplies runtime dependencies and checks the
  `text` it receives; a wrapper such as `exec ./source.sh` does not thereby
  ShellCheck the referenced source. Use it for reusable command-line programs,
  and add an explicit source ShellCheck/package test when source remains in a
  separate file. See the
  [Nixpkgs trivial builders manual](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-writeShellApplication).
- nixpkgs provides a first-class
  [Lychee tester](https://github.com/NixOS/nixpkgs/blob/052c7170b6616f049d374388d3a3a183b404400e/pkgs/build-support/testers/lychee.nix),
  which is preferable to an unpinned network script for link checking.
- Bats is packaged by nixpkgs and can improve shell-test readability, but it is
  an external framework rather than a mandatory Nix idiom; current packaging
  is visible in
  [pkgs/by-name/ba/bats/package.nix](https://github.com/NixOS/nixpkgs/blob/052c7170b6616f049d374388d3a3a183b404400e/pkgs/by-name/ba/bats/package.nix).
- Use `systemd-analyze security` as a review signal, not a universal score gate;
  directives appropriate to a network daemon differ from a one-shot helper.
  See the upstream
  [systemd-analyze manual](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html).
- Restic's own documentation distinguishes repository integrity checking from
  actually restoring data. Use both
  [`restic check`](https://restic.readthedocs.io/en/stable/045_working_with_repos.html#checking-integrity-and-consistency)
  and a restore comparison following the
  [restore documentation](https://restic.readthedocs.io/en/stable/050_restore.html).
- GitHub recommends pinning third-party actions to full commit SHAs as the only
  immutable release form. See
  [Secure use reference](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions).
- GitHub's native
  [dependency review action](https://github.com/actions/dependency-review-action)
  and the
  [OpenSSF Scorecard action](https://github.com/ossf/scorecard-action) are
  relevant public-repository checks, but each should be added with minimal
  permissions and an immutable SHA.

The GitHub source searches above used authenticated `gh search code` and
`gh api` against official `NixOS/nixpkgs` at commit
`052c7170b6616f049d374388d3a3a183b404400e`. Third-party repositories are
identified as such; they are examples, not authorities for this flake.

## Execution graph

```text
P0 baseline and inventory
├── D1 public-data policy ── D2 sanitized topology ── D3 README/docs hub
│                                                    ├── D4 stale docs + issue #2
│                                                    └── D5 links/orphans
├── T1 DNS chaos
├── T2 impermanence reboot
├── T3 restic restore/failure
├── T4 initrd graph
├── S1 shell inventory ── S2 packaged apps ── S3 script tests
│                         └─────────────── S4 systemd hardening
└── C1 CI architecture ── C2 immutable actions ── C3 public security checks

All repository-local tasks ── R1 adversarial review ── G1 final gates
                                              └── O1 authorized operations
```

Run P0 first. D1, T1, T2, T3, T4, S1, and C1 may then proceed concurrently if
their file ownership does not overlap. D2 precedes D3. D3 precedes D4 and D5.
S1 precedes S2 and S4; S2 precedes S3. C1 precedes C2 and C3. O1 is never an
automatic continuation.

## Agent task template

Every implementation agent must:

1. read `AGENTS.md`, this plan, the canonical design, and every file listed in
   its task;
2. verify the reported gap still exists before editing;
3. claim only its task's files and stop on overlapping user changes;
4. use `apply_patch`, preserve educational “why” comments, and avoid broad
   refactors;
5. run task acceptance and mutation tests;
6. run formatting for changed files plus `git diff --check`;
7. inspect the final diff and report residual risks;
8. not commit, push, deploy, close issues, rekey, reboot, or restore live data
   unless separately authorized.

Mutation tests must be named fixture overrides checked into `tests/` or
`modules/_tests/`; never edit production files in place and never put ordinary
fixtures under import-tree-eligible `modules/tests/`. A mutation is valid only
when the named production check fails for the intended reason.

## P0 — Capture a reproducible baseline and test inventory

Priority: P0

Dependencies: none

Recommended agent: `gpt-5.6-luna`, medium effort

Likely files: `docs/archive/testing-baseline.md` (committed evidence destination)

Steps:

1. Record `git status --short`, `nix flake show`, all check attributes, CI jobs,
   scripts, systemd shell fragments, documentation pages, and public SVG text.
   The present tree is intentionally dirty from the preceding implementation
   pass; record the exact status and do not imply a clean-HEAD baseline.
2. Run the existing full gate against `path:.` without modifying the tree, so
   uncommitted source changes are included.
3. Record wall-clock duration and the largest checks so later CI splitting is
   evidence-based.
4. Confirm issue inventory with `gh issue list --state all` and repository
   visibility with `gh repo view`.

Non-goals: fixing failures, changing the lock file, testing live hosts.

Acceptance and mutation tests:

- `nix flake check path:. --keep-going --show-trace` passes from the recorded dirty
  working-tree source.
- Both system closures build with `--no-link`.
- The inventory names every current check exactly once.
- Deliberately querying a nonexistent check fails, proving the inventory script
  does not silently accept missing attributes.

Risk and rollback: read-only except for the plan annotation; revert that single
annotation if evidence is inaccurate.

Suggested commit: `docs(testing): record correctness baseline`

## D1 — Define and enforce the public-data policy

Priority: P0

Dependencies: P0

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `docs/security/public-repository.md`, `docs/README.md`,
`modules/parts/public-repo-checks.nix`, `.gitleaksignore` only if a reviewed
false positive genuinely requires it

Steps:

1. Inventory text extractable from both SVGs, GitHub issue #2, documentation,
   Nix data, comments, and Git history. Classify credentials, personal data,
   sensitive operational metadata, and acceptable public architecture data.
2. State explicitly that RFC 1918 IPs and MACs are not secrets under the repo's
   invariant, while aggregating them with hostnames, interfaces, backups, and
   rescue paths increases reconnaissance value.
3. Record the chosen policy: stop committing/publishing future detailed
   diagrams, retain local operator generation, and record that existing
   commits/issues remain public unless separately rewritten. D2 owns the
   serialized artifact/freshness transition that implements this decision.
4. Define two diagram profiles: `publicOverview` and `operatorDetailed`.
5. Add a deterministic, allowlist-oriented leak check for public-facing files.
   It must reject exact IP/MAC patterns, disk IDs, personal LAN names,
   usernames, interface names, and rescue addressing in the public profile.
6. Keep gitleaks for credentials; do not pretend a generic secret scanner
   implements the topology policy.

Non-goals: treating MAC/IP data as credentials, deleting reservations, rewriting
history, publishing the operator diagram in the README.

Acceptance and mutation tests:

- A synthetic public SVG containing `10.0.0.9`, a MAC, `enp1s0`, or a known
  device label fails the public-profile check.
- The production sanitized profile passes.
- Gitleaks still passes with its default rules; no broad allowlist is added.
- `docs/security/public-repository.md` explains residual exposure from Git
  history and issue #2.
- The selected detailed-diagram policy is explicit and its check matches it.

Risk and rollback: an overbroad regex can flag educational examples. Scope the
check to designated public artifacts and use explicit test fixtures. Revert the
new policy/check files without touching detailed source data.

Suggested commit: `docs(security): define public repository data policy`

## D2 — Generate a sanitized README topology

Priority: P0

Dependencies: D1

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `modules/parts/topology.nix`,
`modules/parts/topology-checks.nix`, `docs/topology/overview.svg`, removal of
tracked `docs/topology/main.svg` and `network.svg`, `.github/workflows/ci.yml`,
`justfile`, and possibly a small helper under `lib/topology/`

Steps:

1. Extend the existing nix-topology data model with a separate public overview;
   do not post-process the detailed SVG with brittle search-and-replace.
2. Generate one composite public overview rather than two README diagrams. This
   is deliberate: one small role-and-flow diagram serves progressive disclosure
   better than separate network/service inventories. Keep detailed views out of
   the README and link architecture prose instead.
3. Show only Internet/upstream DNS, router/LAN trust boundary, Soyo's critical
   DNS/DHCP role, isolated guests, workstation, backup target, and Tailscale
   administration flow.
4. Use an explicit allowed vocabulary for visible labels and SVG element/
   attribute names. Omit addresses, MACs, device nicknames, interface names,
   usernames, service credentials, paths, disk identity, and rescue topology.
5. Reject active content and external fetches: no `script`, `foreignObject`,
   `on*` handlers, remote `href`, CSS `url(http...)`, animation, or embedded
   non-font binary payload. Set a reviewed byte-size ceiling substantially below
   the current 1.68 MB/764 KB detailed outputs and a viewBox/dimension ceiling.
6. Make the generated SVG byte-for-byte deterministic and include it in the
   topology freshness check.
7. Parse its XML structure (not regex alone), extract visible text, enforce the
   allowed vocabulary, and apply D1's prohibited-token policy.
8. Remove `docs/topology/main.svg` and `network.svg` from future publication and
   CI artifacts/freshness checks while preserving a documented local
   operator-detailed build command. Do not rewrite commits that already contain
   them.

Non-goals: removing or degrading the local `operatorDetailed` generator,
hand-editing generated SVG, changing network configuration.

Acceptance and mutation tests:

- Two clean builds produce identical `overview.svg` hashes.
- Repeated evidence uses independent builds, for example two fresh store outputs
  or `nix build --rebuild`, not two reads of the same cached path.
- `nix build .#checks.x86_64-linux.topology-freshness --no-link` passes.
- Injecting one real reservation IP or MAC into the public model causes the
  public leak check to fail.
- The image remains legible at GitHub README width; D3 owns useful accessible
  alt text at the Markdown embedding site.
- Fixtures containing `<script>`, an event handler, external URL, unexpected
  label, excessive dimensions, or excessive bytes each fail by fixture name.

Risk and rollback: topology library updates can change bytes. Keep the profile
source declarative and let freshness failure explain regeneration. Revert the
new output/profile without changing detailed diagrams.

Suggested commit: `feat(topology): add sanitized public overview`

## D3 — Replace the README with a concise visual entry point

Priority: P0

Dependencies: D2

Recommended agent: `gpt-5.6-luna`, high effort

Likely files: `README.md`, `docs/README.md`

Steps:

1. Reduce README to no more than 800 words, roughly 80–120 lines, and no more
   than three badges: one-sentence purpose, sanitized topology, two-host table,
   five design principles, minimal
   quick start, and “learn / operate / contribute” links.
2. Remove the hand-maintained module tree, exhaustive tooling table, repeated
   architecture prose, and detailed operational commands. Link deeper instead.
3. Create `docs/README.md` as the navigation root with progressive disclosure:
   - **Start here:** design overview and guided learning path;
   - **Operate:** install, update/rollback, backup/restore, recovery, secrets;
   - **Understand:** canonical specs and focused subsystem docs;
   - **Contribute:** AGENTS rules, test architecture, adding hosts/services;
   - **History:** dated specifications and completed implementation plans.
4. Give every current authoritative document one primary category; contextual
   deep links elsewhere remain welcome.
5. Do not include a module/file inventory. Confirm the diagram and host table
   remain usable at narrow/mobile GitHub widths.
6. Use relative links and descriptive alt text. Avoid remote decorative images
   except existing badges that pass the public-data policy.

Non-goals: rewriting long-form docs, moving many files, embedding detailed
topology, duplicating AGENTS.md.

Acceptance and mutation tests:

- README is under the agreed line/word budget and renders without raw broken
  HTML.
- A new visitor can reach install, recovery, secrets, canonical design, and
  learning docs in at most two clicks.
- Removing a document's only primary-category link makes D5 fail; removing one
  of several contextual links does not.
- Markdownlint passes.

Risk and rollback: shortening may hide an important entry point. Preserve
content in its canonical document before deleting prose. Revert README/docs hub
only; no runtime behavior changes.

Suggested commit: `docs(readme): create concise visual project guide`

## D4 — Reconcile active, stale, and historical documentation

Priority: P1

Dependencies: D3

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `docs/README.md`, `docs/status.json` or `docs/status.nix`,
`docs/install-soyo.md`,
`hosts/zbook/INSTALL.md`, `docs/archive/hyprland-desktop.md`,
`docs/superpowers/plans/*.md`, `docs/superpowers/specs/*.md`, issue #2 comment
only after explicit authorization

Steps:

1. Create one shared machine-readable status manifest and classify each document
   as canonical, active, completed, superseded, or historical. Use “completed”
   or “superseded” only when evidence supports it; age alone is insufficient.
   Generate/check banners from the manifest rather than maintaining divergent
   hand-written status claims.
2. Use a minimal-move strategy: add navigation and status metadata first;
   rename or move only when ambiguity cannot be solved with a banner. Preserve
   GitHub links and history where practical.
3. Audit `hosts/zbook/INSTALL.md` against current Sway/DMS and NVIDIA code;
   remove or label historical COSMIC workarounds that have no implementation.
4. Decide whether `docs/archive/hyprland-desktop.md` is current, future, or historical;
   make its status visible and link it from only the matching docs-hub section.
5. Compare issue #2 step-by-step with `docs/install-soyo.md`: disk safety gate,
   pre-wipe build, blank snapshot, initrd/stage-2 keys, agenix rekey, TPM phase,
   install, first boot, DHCP cutover, and verification.
   Issue #2 contains exact disk, LAN, and interface data, but no direct-link
   rescue address; do not attribute one to it.
6. Preserve the issue body in GitHub history by closing rather than editing or
   deleting it. Before requesting approval, commit a checklist mapping every
   issue section to its canonical replacement and record current state/URL.
7. If and only if no unique safety information remains, prepare a concise issue
   comment linking the canonical runbook and summarizing supersession. Request
   approval before `gh issue close 2 --comment ...`.

Non-goals: silently deleting history, executing issue commands without
approval, changing boot or secrets behavior.

Acceptance and mutation tests:

- Every dated plan has a manifest-backed, evidence-correct status.
- `rg -n 'cosmic|Hyprland' README.md docs hosts/zbook` finds only explicitly
  current or clearly historical claims.
- A checklist demonstrates every still-valid issue #2 safety gate exists in an
  active runbook.
- Before approval, issue #2 remains open. After separately approved closure,
  `gh issue view 2 --json state` reports `CLOSED` and contains the replacement
  link.

Risk and rollback: loss of operational knowledge is the main risk. Copy unique
instructions before reducing historical pages. GitHub issue closure is
reversible but external; keep it outside the repository commit.

Suggested commit: `docs(navigation): distinguish active and historical guides`

## D5 — Enforce links, anchors, and documentation discoverability

Priority: P1

Dependencies: D3, D4

Recommended agent: `gpt-5.6-luna`, medium effort

Likely files: `modules/parts/docs-checks.nix`, `docs/README.md`,
`.github/workflows/ci.yml` only if external links are split into a scheduled job

Steps:

1. Add an offline flake check for relative files, Markdown anchors, README image
   targets, and orphaned active docs. Exclude generated/historical internals
   only through an explicit inventory.
2. Use the pinned nixpkgs Lychee tester where it fits. Keep deterministic local
   checks in `nix flake check`; run unstable external HTTP checks on a scheduled
   or manually triggered CI job with retry/cache policy.
3. Define the navigation roots (`README.md`, `docs/README.md`, `AGENTS.md`) and
   fail when an active document has no primary category. Additional contextual
   links are allowed and must not be treated as duplicate ownership.
4. Check case sensitivity, percent-encoded paths, and anchors using explicit
   GitHub-slug fixtures for duplicate headings, punctuation, Unicode, inline
   code, and repeated suffixes. Do not claim generic Markdown-anchor semantics
   are identical without these fixtures.

Non-goals: making ordinary PR checks depend on the public Internet, hiding
broken links in a blanket exclusion.

Acceptance and mutation tests:

- Renaming a target, changing an anchor, or adding an unlinked active Markdown
  file fails the local check.
- Known historical plans remain reachable through the History index.
- A simulated transient external failure does not block the deterministic PR
  gate but is visible in the scheduled check.

Risk and rollback: anchor implementations differ. Pin and test the chosen
checker against headings used here. Revert the check module if it produces
unactionable false positives; do not remove navigation links to satisfy it.

Suggested commit: `test(docs): enforce links and discoverability`

## T1 — Add DNS/DHCP chaos and critical-role isolation tests

Priority: P0

Dependencies: P0

Recommended agent: `gpt-5.6-sol`, extra-high effort

Likely files: `modules/parts/dns-dhcp-vm-check.nix`, with split fixtures under
`modules/_tests/dns-dhcp/` or root `tests/dns-dhcp/`; possibly
`modules/nixos/blocky.nix` and `modules/nixos/dhcp.nix` only for defects exposed

Steps:

1. Refactor the existing VM test into named phases without weakening current
   packet-level assertions.
2. Add an in-test upstream DNS node and remove external network dependence.
3. Test upstream outage and recovery: cached answer behavior, bounded failure
   for uncached names, and service recovery without restart.
4. Stop dnsmasq and prove forward DNS remains available while reverse/DHCP fail
   in the expected bounded way; restart it and prove lease/PTR recovery.
5. Stop Blocky and prove dnsmasq DHCP ownership remains intact; restart Blocky
   and prove port ownership and forward DNS recovery.
6. Apply bounded memory/CPU pressure to a guest unit and record that Blocky and
   dnsmasq remain responsive in this smoke scenario. This is regression evidence,
   not proof of isolation under all real resource-exhaustion conditions. Use
   deterministic limits and timeouts, not runner saturation.
7. Test malformed/duplicate DHCP traffic or lease contention only if available
   tooling makes the assertion deterministic; otherwise document it as a later
   packet-fuzzing experiment.
8. Capture journals on failure and keep total runtime suitable for CI.

Non-goals: Internet DNS, production network contact, benchmarking QPS, changing
DNS ownership, probabilistic stress tests.

Acceptance and mutation tests:

- Existing happy-path assertions still pass.
- Each service stop creates only its intended failure domain and recovers within
  an explicit deadline.
- Removing Blocky's reverse-zone forwarding fails the PTR phase.
- Removing guest resource limits fails either the isolation invariant or the
  controlled-pressure phase.
- The test passes at least three independent executions using `--rebuild` or
  fresh derivation salts/outputs; repeatedly reading one cached store result is
  not repeatability evidence.

Risk and rollback: VM timing and DHCP clients are flake-prone. Prefer
`wait_until_succeeds`, explicit journal assertions, isolated VLANs, and bounded
timeouts from the NixOS test-driver manual. Split slow chaos from the fast smoke
check if runtime grows excessively.

Suggested commit: `test(soyo): exercise DNS and DHCP failure isolation`

## T2 — Prove impermanence with a rebooting VM

Priority: P0

Dependencies: P0

Recommended agent: `gpt-5.6-sol`, extra-high effort

Likely files: `modules/parts/impermanence-vm-check.nix`, fixtures under
`modules/_tests/impermanence/` or root `tests/impermanence/`,
`modules/nixos/persistence.nix` only for proven
defects

Steps:

1. Build a minimal VM using the real persistence aspect and a test disk layout;
   avoid coupling to physical facter output or TPM.
2. Boot once, write distinct sentinels to ephemeral root, declared durable
   system state, declared durable user state, and an intentionally undeclared
   state path.
3. Reboot through the actual initrd rollback path.
4. Prove the root sentinel and undeclared state disappear, while declared state,
   machine ID, SSH host identity, and selected service state survive with
   correct ownership/mode.
5. Repeat a second reboot to catch one-time initialization artifacts.
6. Add named override fixtures for missing `/persist` early-boot availability.
   If the invariant is a Nix assertion, test evaluation failure with a focused
   `builtins.tryEval`/module-evaluation fixture. If the defect is intentionally
   build-time, construct the failing child derivation and wrap it with the
   pinned nixpkgs `pkgs.testers.testBuildFailure'` API so the wrapper succeeds
   only for the expected failure/status/log pattern. Do not put an intentionally
   failing child directly in the flake's normal check set.

Non-goals: emulating Secure Boot/TPM, using the production disk, asserting that
all caches survive.

Acceptance and mutation tests:

- Two consecutive reboots prove the positive and negative persistence sets.
- Removing a required preservation entry fails a specific sentinel assertion.
- Disabling rollback causes the ephemeral-root assertion to fail.
- File owner, group, and mode checks catch overly permissive persistence.
- Repeat the reboot derivation independently with `--rebuild` or distinct
  outputs; a cached success is not a second boot test.

Risk and rollback: VM disk plumbing can accidentally test a fake cleanup rather
than the real initrd unit. Assert the rollback unit ran via journal and inspect
the mounted subvolume. Revert the standalone check if it cannot faithfully use
the production aspect.

Suggested commit: `test(persistence): verify wipe and preservation across reboot`

## T3 — Test restic backup, restore, corruption, and failure reporting

Priority: P0

Dependencies: P0

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `modules/parts/backup-vm-check.nix` or
`modules/parts/backup-integration-check.nix`, fixtures under
`modules/_tests/backup/` or root `tests/backup/`,
`modules/nixos/backup.nix` only for defects

Steps:

1. Use a temporary local restic repository in a derivation or isolated VM. Do
   not contact the NAS or use production secrets.
2. Create representative files including empty files, permissions, symlinks,
   nested paths, and names with spaces; back them up through the real module's
   command/unit where practical.
3. Copy the completed deterministic fixture repository before corruption tests.
   Run `restic check --read-data` on the intact copy, restore to a fresh
   directory, and compare contents plus relevant metadata. Run corruption
   mutations only on separate copies so fixture order cannot mask damage.
4. Delete source data before restore so the test cannot pass by comparing the
   original tree to itself.
5. Test wrong password, unavailable repository, read-only target, and deliberate
   pack/index corruption. Assert nonzero status, useful journal output, metric
   failure state, and notification handoff without making a real network call.
6. Prove a later successful backup clears or supersedes the failure signal.

Non-goals: using live backup credentials, destructive prune on production,
claiming repository check alone proves restorability.

Acceptance and mutation tests:

- A real backup, `check`, destructive source removal, restore, and recursive
  comparison all pass.
- The integrity assertion specifically executes `restic check --read-data` on a
  deterministic copied repository.
- Corrupting one restored byte fails comparison.
- Each failure fixture returns nonzero and records the expected metric/status.
- Notification transport is stubbed at the boundary and receives no secret
  material in arguments or logs.

Risk and rollback: corruption tests can be destructive if paths escape the
fixture. Assert all repositories are under `$TMPDIR`/VM disks before mutation.
Revert only test fixtures or the smallest module fix exposed.

Suggested commit: `test(backup): prove restic restore and failure semantics`

## T4 — Verify initrd recovery artifacts and dependency graph

Priority: P1

Dependencies: P0

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `modules/parts/initrd-invariants.nix`,
`modules/parts/initrd-vm-check.nix`, `modules/nixos/remote-unlock.nix`,
`modules/nixos/persistence.nix`

Steps:

1. Evaluate the real Soyo initrd config and assert required SSH host-key path,
   authorized keys, cryptsetup tooling, network addresses, rescue route, port,
   and firewall/listener ownership are present without secret contents.
2. Assert the upstream-derived `boot.initrd.secrets` destination-to-source
   mapping created from `boot.initrd.network.ssh.hostKeys`, including the
   runtime `/boot/initrd-ssh/...` source and initrd destination. A string source
   is copied by `initrd-nixos-copy-secrets.service` at boot; it is deliberately
   not a Nix path/store input. Never require, open, hash, print, or search for
   the production private-key payload in a built archive.
3. Inspect the evaluated initrd systemd unit relationships: `/persist`
   availability and
   rollback ordering must precede consumers; network and sshd must not create a
   boot cycle; normal boot must not wait forever for rescue networking.
4. Inspect only non-secret build-time artifacts: required binaries, generated
   units, sshd configuration, public authorized keys, destination paths, and the
   copy-secrets ordering. Prove no operator master identity is a store reference;
   do not make assertions about a production runtime key payload being absent or
   present in an archive that should never ingest it.
5. If reliable under QEMU, use a named fixture-only SSH host key and add a
   non-destructive smoke boot that reaches the
   encrypted-root prompt and exposes initrd SSH on an isolated network. Keep
   full unlock and physical direct-link behavior in the manual boundary.

Non-goals: TPM emulation as proof of physical PCR behavior, real LAN access,
embedding private host key contents in outputs.

Acceptance and mutation tests:

- Removing an ordering edge, initrd key declaration, or SSH authorized key
  fails a focused assertion.
- The evaluated initrd secret mapping and sshd ordering match upstream runtime
  copy semantics, without dereferencing production private-key sources.
- A focused graph check or `systemd-analyze verify` against materialized
  evaluated initrd units reports no cycles/missing dependencies. Do not run it
  against host-system units or claim it validates Nix-only dependencies it was
  not given.

Risk and rollback: initrd inspection can accidentally copy secrets into a test
output. Match option values, destination/source path strings, public keys, and
fixture keys only; never read production private contents. Revert the standalone check if safe redaction cannot be
guaranteed.

Suggested commit: `test(initrd): verify remote unlock boot graph`

## S1 — Inventory shell boundaries and enable strict checking

Priority: P0

Dependencies: P0

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `modules/nixos/*.nix`, `modules/parts/shell-checks.nix`,
`docs/testing.md`

Steps:

1. Inventory every `script`, `preStart`, `postStart`, `ExecStart` shell store
   path, `writeShellScript`, heredoc, and standalone `.sh` file.
2. Classify fragments as systemd inline scripts, reusable applications, tiny
   ExecStart commands, or test fixtures.
3. Enable `enableStrictShellChecks = true` only on NixOS systemd unit script
   options that the module system renders/checks (`script`, `preStart`,
   `postStart`, and supported peers). It does not validate arbitrary `ExecStart`
   strings or the contents of a separately created `writeShellScript`.
4. Cover each `ExecStart` string with systemd argument/command validation and
   each `writeShellScript`/standalone source with an explicit ShellCheck build
   test. For `writeShellApplication`, test the actual source text, not only a
   wrapper that execs another file.
5. Ensure all command paths are explicit or supplied by `runtimeInputs`; remove
   accidental ambient `PATH` dependencies.
6. Add an evaluation/build check that prevents new unchecked nontrivial shell
   fragments from bypassing the inventory.

Non-goals: converting every two-token ExecStart into an app, globally enabling
hardening directives without service analysis, changing behavior for style.

Acceptance and mutation tests:

- Strict module checks cover applicable script options, while inventory-backed
  source/package tests separately cover `ExecStart`, `writeShellScript`, and
  standalone sources.
- Removing a runtime input or introducing an undefined variable fails the
  build/check.
- ShellCheck continues to cover all tracked `.sh` files.
- The documented exceptions list is empty or each entry names an upstream
  incompatibility and owner.

Risk and rollback: strict mode may change expected pipeline behavior. Add
fixtures before refactoring and revert per service, not as a global disable.

Suggested commit: `refactor(shell): enforce strict systemd script checks`

## S2 — Package operational scripts as first-class flake apps

Priority: P1

Dependencies: S1

Recommended agent: `gpt-5.6-luna`, high effort

Likely files: `modules/parts/perSystem.nix`, `scripts/healthcheck.sh`,
`scripts/recover-secrets.sh`, `scripts/set-tailscale-keys.sh`, `justfile`,
`docs/README.md`, relevant runbooks

Steps:

1. Keep reusable logic in versioned source files, but package each command with
   `writeShellApplication` and complete `runtimeInputs`. Either pass the actual
   source as its checked `text` or add an explicit ShellCheck/package test for
   the separate source; a one-line `exec` wrapper is not source coverage.
2. Expose explicit flake apps/packages with stable names and help output. Make
   destructive or secret-handling commands refuse noninteractive ambiguity and
   validate host/name/path inputs before mutation.
3. Replace stringly remote shell pipelines where practical with small,
   separately quoted remote commands. Pass data through stdin/environment only
   when semantics are clear; never interpolate untrusted host/name input into a
   remote shell string.
4. Standardize exit codes, stdout/stderr, `--help`, `--dry-run`, and machine-
   readable output where health checks or CI consume it.
5. Make `just` recipes thin aliases to flake apps, not a second implementation.

Non-goals: running recovery or key setup, adding a general CLI framework,
putting secrets in the Nix store.

Acceptance and mutation tests:

- Each app builds and `--help` works in a clean environment with an empty or
  minimal `PATH`.
- Missing runtime inputs fail a package test.
- Invalid host, role, interface, or secret name is rejected before SSH/Nix
  invocation.
- `--dry-run` produces no filesystem, remote, or Git mutation.

Risk and rollback: packaging secret recovery can accidentally make private
paths store dependencies. Keep private paths as runtime strings and test Nix
closure references. Revert one app at a time; retain source scripts until all
callers migrate.

Suggested commit: `refactor(cli): package operational scripts as flake apps`

## S3 — Replace ad hoc shell tests with a structured contract suite

Priority: P1

Dependencies: S2

Recommended agent: `gpt-5.6-luna`, high effort

Likely files: root `tests/scripts/`, `modules/parts/healthcheck-tests.nix`, new
`modules/parts/script-tests.nix`

Steps:

1. Choose the smallest appropriate harness after a spike: Bats can improve
   setup/teardown and assertion readability, while pure shell remains valid if
   it is clearer and all branches are explicit. Record the decision in
   `docs/testing.md`.
2. Test all three apps at command boundaries using temporary directories and
   deterministic stubs for SSH, sudo, Nix, age/rage, curl, and systemctl.
3. Cover help, argument validation, role detection, quoting, spaces, remote
   failure, timeout, partial output, privilege failure, dry run, cleanup traps,
   and secret redaction.
4. Avoid rewriting fixture executables in place with `sed`; build fixtures with
   known interpreters or package them as test dependencies.
5. Emit TAP/JUnit only if CI consumes it; otherwise keep derivation logs simple.

Non-goals: mocking implementation internals, contacting hosts, snapshotting
large unstable output.

Acceptance and mutation tests:

- Branch coverage inventory maps every documented exit status to a test.
- A stub that receives an unsafely split argument makes the test fail.
- A fake secret printed to stdout/stderr makes the redaction test fail.
- Tests run hermetically through `nix build` and repeatedly without host state.

Risk and rollback: over-mocking can certify the harness rather than the app.
Keep a few package-level black-box tests with real local tools. Revert harness
migration while preserving newly discovered regression cases.

Suggested commit: `test(cli): add hermetic operational command contracts`

## S4 — Audit systemd sandboxing and service failure semantics

Priority: P1

Dependencies: S1

Recommended agent: `gpt-5.6-sol`, extra-high effort

Likely files: `modules/nixos/{backup,maintenance,observability,tailscale,blocky,dhcp}.nix`,
`modules/parts/systemd-hardening-checks.nix`, `docs/security/service-hardening.md`

Steps:

1. For each custom/helper service, document required filesystem writes, network
   families, capabilities, devices, namespaces, credentials, and state.
2. Add compatible hardening such as `NoNewPrivileges`, `PrivateTmp`,
   `ProtectSystem`, `ProtectHome`, `ProtectKernel*`, `RestrictAddressFamilies`,
   `CapabilityBoundingSet`, `RestrictNamespaces`, `LockPersonality`,
   `MemoryDenyWriteExecute`, and explicit `ReadWritePaths`—but only when tested.
3. Keep Blocky and dnsmasq availability ahead of chasing a score. Treat
   `systemd-analyze security` on the materialized generated units as a review
   aid and compare only reviewed directives against a per-unit baseline. Do not
   impose a universal numeric threshold or claim it verifies runtime access.
4. Verify restart policy, start-limit behavior, timeout, watchdog/readiness where
   supported, and failure notification loops. A notification failure must not
   recursively trigger itself or impair DNS/DHCP.
5. Extend guest isolation checks to reject privilege growth and unexpected
   writable paths for the explicit guest inventory.

Non-goals: blindly applying every directive, sandboxing away required backup
access, changing critical-role resource policy without a design decision.

Acceptance and mutation tests:

- Every custom service has a capability/write/network rationale.
- Removing a required hardening directive from a reviewed helper fails the
  invariant check.
- VM smoke tests prove each hardened service starts and performs its core task.
- Forced repeated helper failure is bounded and does not restart-loop or affect
  DNS/DHCP health.

Risk and rollback: incorrect hardening causes delayed operational failure.
Commit by service group, use VM tests before live deployment, and roll back the
specific directive rather than disabling the policy globally.

Suggested commit: `harden(systemd): constrain custom service privileges`

## C1 — Redesign CI around explicit, nonduplicated gates

Priority: P1

Dependencies: P0

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `.github/workflows/ci.yml`, `modules/parts/perSystem.nix`,
`justfile`, `docs/testing.md`

Steps:

1. Use P0 timing evidence to define jobs: fast static checks, pure evaluation,
   VM/integration checks, host closure matrix, artifacts, and scheduled external
   checks.
2. Ensure `nix flake check` is not redundantly rebuilding host closures already
   built in the matrix. Select named checks per job or use one authoritative
   whole-flake job and make other jobs reporting-only.
3. Express dependencies with `needs`; run independent work concurrently and
   keep topology publication downstream of freshness/security checks.
4. Keep permissions read-only by default and grant job-level permissions only
   where required. Never expose Cachix secrets to untrusted fork PR execution.
5. Preserve `--no-link --print-out-paths` and cancellation. Remove the current
   `previous-closure.txt` comparison unless both previous and current closures
   are demonstrably realized in the same store: caching only a store-path string
   does not make that closure available, and a fixed `actions/cache` key is not
   a reliable rolling history. If closure diffs remain, build/fetch the PR base
   closure explicitly, verify `nix path-info` for both paths, and fail/label the
   comparison as unavailable rather than presenting an empty success.
6. Add timeouts and artifact retention periods to every expensive job.

Non-goals: optimizing away coverage, self-hosted runners, deploying from CI,
making network-dependent checks block every PR.

Acceptance and mutation tests:

- `actionlint` passes.
- A job/flake-check coverage table proves every required gate runs once in the
  intended trigger class.
- A fork-PR event simulation/review proves no write token or Cachix secret is
  exposed.
- Deliberately failing one VM check blocks closure/topology success as designed.
- A closure-diff integration fixture proves both closures exist; otherwise the
  feature is removed instead of retained as best-effort decoration.

Risk and rollback: cache/job restructuring can increase cost. Land graph changes
separately from test additions and compare timings over several runs.

Suggested commit: `ci(pipeline): separate fast and integration gates`

## C2 — Pin GitHub Actions to reviewed immutable commits

Priority: P0

Dependencies: C1

Recommended agent: `gpt-5.6-luna`, medium effort

Likely files: `.github/workflows/ci.yml`, `renovate.json`,
`docs/security/supply-chain.md`

Steps:

1. Resolve every `uses:` reference to the reviewed full 40-character commit SHA
   for its current release. Preserve the release tag in a trailing comment.
2. Configure Renovate to propose action digest updates with release notes; do
   not enable automerge for actions that handle tokens, caches, or artifacts.
3. Record source repository, publisher, permissions, inputs, and reason for each
   action. Prefer GitHub-owned actions where functionality is equivalent.
4. Review cache and artifact action behavior for poisoning, overwrite, hidden
   files, retention, and fork boundaries.

Non-goals: pinning to a mutable tag plus a fake comment, updating `flake.lock`,
adding unnecessary actions.

Acceptance and mutation tests:

- A check requires full 40-character SHAs for remote `owner/repo/path@ref`
  actions. Repository-local actions using `./path` are permitted and are bound
  to the checked-out revision; Docker actions and reusable workflows receive an
  explicit reviewed rule rather than being accidentally matched as local.
- `actionlint` passes.
- Renovate dry-run/config validation recognizes GitHub Actions digest updates.
- Replacing one SHA with `@v4` fails the immutable-action check.

Risk and rollback: a wrong SHA breaks CI. Verify SHA belongs to the expected
upstream tag through the GitHub API and sign/release metadata where available.
Rollback to the previous reviewed SHA, never to a floating tag.

Suggested commit: `ci(security): pin actions to immutable commits`

## C3 — Add proportionate public-repository security checks

Priority: P1

Dependencies: C1, C2, D1

Recommended agent: `gpt-5.6-terra`, high effort

Likely files: `.github/workflows/security.yml`, `renovate.json`,
`SECURITY.md`, `docs/security/supply-chain.md`, GitHub repository settings only
after explicit authorization

Current posture recorded through authenticated read-only GitHub API on
2026-07-12:

- repository visibility is public;
- Actions are enabled for all actions and SHA pinning enforcement is disabled;
- default workflow token permission is read, and it cannot approve PR reviews;
- `main` has no branch protection and there are no repository rulesets;
- secret scanning, non-provider patterns, validity checks, and push protection
  are disabled;
- Dependabot vulnerability alerts and Dependabot security updates are disabled;
- private vulnerability reporting is disabled.

These are observations, not permission to change settings.

Steps:

1. Add dependency review for pull requests if it understands the repository's
   dependency surfaces; verify value for `flake.lock`, npm lock files, and
   actions before making it required.
2. Evaluate OpenSSF Scorecard in read-only mode with minimal permissions and a
   pinned SHA. Upload SARIF only if code-scanning permissions and public results
   are intentionally accepted.
3. Distinguish scans explicitly: preserve the deterministic working-tree scan
   (`detect --source . --no-git` for the pinned version), and add a separately
   named full-Git-history scan using that version's supported history command.
   Pass `--redact` (and test redaction) to both CI scans. Never describe the
   working-tree scan as history coverage or print findings containing values.
4. Add `SECURITY.md` with a private reporting route only after that route exists,
   and an explicit statement
   that public issues must not contain credentials, exact recovery material, or
   new sensitive topology.
5. Prepare separate authorization requests for: secret scanning, push
   protection, private vulnerability reporting, Dependabot vulnerability alerts,
   Dependabot security updates, a `main` branch protection/ruleset with required
   checks, and repository-level Actions SHA enforcement. Re-read settings before
   each mutation; availability may depend on GitHub plan/public-repo features.
   Do not combine these external mutations with a repository commit.

Non-goals: CodeQL for Nix without demonstrated signal, granting blanket
`security-events: write`, exposing operational vulnerabilities in public issues,
automatic dependency merge.

Acceptance and mutation tests:

- All actions are SHA-pinned and job permissions are least-privilege.
- Fork PRs cannot access repository secrets or writable tokens.
- A fixture credential and a prohibited topology token both fail their distinct
  checks without echoing the full value.
- Working-tree and history fixtures prove their named scans differ, and logs
  contain redaction rather than the fixture value.
- A post-change `gh api` report (only after approval) records exact enabled
  settings; until then, documentation continues to state the disabled posture.
- Security workflow failure is actionable and does not duplicate the same scan
  in three jobs.

Risk and rollback: public SARIF/Scorecard results may reveal configuration
weaknesses. Decide publication before enabling upload. Revert the workflow and
remove external setting changes separately.

Suggested commit: `ci(security): add public repository safeguards`

## R1 — Adversarial cross-task review

Priority: P0 final review

Dependencies: all repository-local tasks selected for the milestone

Recommended agent: `gpt-5.6-sol`, extra-high effort

Likely files: review-only; fixes should return to the owning task agent

Steps:

1. Review the combined diff against all ten hard invariants and boundary rules.
2. Try to defeat each new check: false positive, false negative, test that only
   tests its fixture, leaked secret through logs/store closure, network access,
   timing flake, disabled check, or CI path that never runs.
3. Confirm README/public overview reveal no prohibited topology while remaining
   useful and honest.
4. Confirm docs status/navigation cannot lead an operator from current guidance
   into a historical command sequence.
5. Confirm issue #2 was not mutated without authorization.
6. Return findings by severity and exact file/line; do not silently broaden the
   implementation scope.

Non-goals: style churn, deployment, approving one's own implementation without
mutation testing.

Acceptance: zero unresolved critical/high findings; every lower finding is fixed
or explicitly accepted with rationale.

Risk and rollback: review-only.

Suggested commit: none.

## G1 — Staged final validation gates

Priority: P0 release gate

Dependencies: R1 findings resolved

Recommended agent: `gpt-5.6-terra`, high effort for execution; `gpt-5.6-sol`,
high effort for interpreting any cross-cutting failure

Run in stages so failures stay attributable.

### Gate A: source and documentation

```bash
nix build .#checks.x86_64-linux.pre-commit --no-link
nix fmt -- --ci
nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose --redact
git diff --check
```

Also run the new offline link/orphan, public-data, immutable-action, and strict
shell checks explicitly by attribute.

### Gate B: pure evaluation and evaluation-negative controls

```bash
nix flake check path:. --no-build --show-trace
```

Run evaluation-negative fixtures here. Do not claim `--no-build` executed
`testBuildFailure'`, VM, shell-package, corruption, or other build-time negative
controls.

### Gate C: VM and integration tests

Build DNS/DHCP smoke and chaos, impermanence reboot, restic restore/failure,
initrd smoke, CLI contracts, and hardened-service smoke checks individually,
then run the complete flake check:

```bash
nix flake check path:. --keep-going --show-trace
```

Run build-time negative/mutation wrappers here and prove their named child
fixture fails for the expected reason. Repeat timing-sensitive VM checks at
least three independent times with `--rebuild` or distinct derivation outputs;
cached path lookup is not a repeat.

### Gate D: full closures and CI definition

```bash
nix build path:.#nixosConfigurations.soyo.config.system.build.toplevel --no-link
nix build path:.#nixosConfigurations.zbook.config.system.build.toplevel --no-link
```

Run Actionlint and verify every remote action reference is a full SHA. Inspect
closure references to ensure operator private-key paths or fixture secrets did
not enter the store.

### Gate E: public rendering

Render README and docs locally or inspect on a branch/PR. Verify the sanitized
diagram at desktop/mobile widths, alt text, all navigation paths, and GitHub
anchor behavior. Extract SVG text and retain the public-data check output.

No gate may be marked green when a command was skipped. Record skipped checks
as explicit blockers or authorized deferrals.

## O1 — Operational and manual verification boundary

Priority: post-merge/deployment only

Dependencies: G1, explicit user authorization, recovery window

Recommended agent: `gpt-5.6-sol`, extra-high effort for a supervised runbook;
the human operator remains the decision-maker

Repository tests cannot prove physical firmware, TPM PCR behavior, power-loss
recovery, real DHCP cutover, NAS availability, or restore quality on actual
hardware. Split these into separately authorized sessions:

1. non-destructive build/deploy and live health checks for one host at a time;
2. live DNS/DHCP failover and guest-pressure observation on Soyo, explicitly
   recorded as observation rather than proof;
3. controlled reboot and TPM auto-unlock;
4. LAN initrd SSH and direct-link rescue;
5. passphrase fallback and TPM re-enrollment;
6. Secure Boot tamper rejection;
7. forced helper failure and ntfy delivery;
8. restic restore drill to an isolated destination with hash/application checks;
9. disk/power-loss rehearsal only with current backups and physical access.

Each session needs a preflight checklist, success/abort criteria, console access,
rollback generation, backup freshness evidence, and an operator-written result.
Any intentional DNS/DHCP outage additionally requires an announced maintenance
window, an alternate DNS/DHCP or static-client recovery path, local console
access, a maximum outage timer, and an immediate service/generation rollback
command rehearsed before stopping either critical role.
Do not combine destructive drills. Do not automate away passphrase confirmation
or TPM slot selection.

Suggested commit: `docs(operations): record resilience drill results` only for
redacted, non-sensitive outcomes.

## Concurrency and file-ownership matrix

| Track | Tasks | Exclusive files | May run with |
| --- | --- | --- | --- |
| Public docs | D1–D5 | `README.md`, `docs/README.md`, topology docs | T1–T4, S1 |
| DNS/DHCP | T1 | DNS/DHCP VM tests | D1, T2–T4, C1 |
| Persistence | T2 | impermanence VM tests | D1, T1, T3–T4, C1 |
| Backup | T3 | backup integration tests | D1, T1–T2, T4, C1 |
| Initrd | T4 | initrd checks | D1, T1–T3, C1 |
| Shell/apps | S1–S4 | scripts and service modules | docs tasks after coordination |
| CI | C1–C3 | `.github/workflows/*`, `renovate.json` | tests until checks are wired |
| Review | R1/G1 | no ownership during review | nothing that mutates files |

Rules:

- Only one agent edits `modules/parts/perSystem.nix`, `README.md`,
  `.github/workflows/ci.yml`, or a shared service module at a time.
- T1–T4 may build isolated test files concurrently, but any production-module
  fix is serialized through a single production lock. In particular S4 may not
  overlap production edits to `blocky.nix`, `dhcp.nix`, `persistence.nix`,
  `remote-unlock.nix`, or `backup.nix`; T4 and T2 also serialize changes to
  `persistence.nix`.
- Test agents may fix a production defect only after notifying the owner and
  limiting the patch to the demonstrated failure.
- D5 and C1 coordinate CI wiring: D5 owns check implementation; C1 owns job
  placement.
- D2 owns topology generation; D3 only embeds the produced public artifact.
- D1 and D2 are serialized: D1 records the exposure decision and D2 exclusively
  removes tracked detailed artifacts and rewires freshness/CI/local generation.
- S2 owns script packaging; S3 owns tests after S2's interface is stable.
- R1 begins only after all implementation agents are idle.

## Affordable model allocation

Use stronger models only where failure semantics or boot/security reasoning
justify them:

| Task | Model | Effort |
| --- | --- | --- |
| P0 | `gpt-5.6-luna` | medium |
| D1 | `gpt-5.6-terra` | high |
| D2 | `gpt-5.6-terra` | high |
| D3 | `gpt-5.6-luna` | high |
| D4 | `gpt-5.6-terra` | high |
| D5 | `gpt-5.6-luna` | medium |
| T1 | `gpt-5.6-sol` | extra-high |
| T2 | `gpt-5.6-sol` | extra-high |
| T3 | `gpt-5.6-terra` | high |
| T4 | `gpt-5.6-terra` | high |
| S1 | `gpt-5.6-terra` | high |
| S2 | `gpt-5.6-luna` | high |
| S3 | `gpt-5.6-luna` | high |
| S4 | `gpt-5.6-sol` | extra-high |
| C1 | `gpt-5.6-terra` | high |
| C2 | `gpt-5.6-luna` | medium |
| C3 | `gpt-5.6-terra` | high |
| R1 | `gpt-5.6-sol` | extra-high |
| G1 | `gpt-5.6-terra` | high |

`gpt-5.4-mini` at medium effort is acceptable only for P0 inventory formatting
or a mechanical link-list update after D5's policy exists. It should not own
topology classification, tests, shell quoting, CI permissions, secrets, boot,
backup, or systemd hardening.

## Definition of done

The program is complete when:

- README is concise, attractive, and embeds only the sanitized deterministic
  topology overview;
- `docs/README.md` provides two-click progressive discovery and active docs are
  neither broken nor orphaned;
- historical plans are visibly historical, current runbooks agree with code,
  and issue #2 is reconciled (closure only if separately authorized);
- DNS/DHCP failure domains and recovery are VM-tested without Internet access;
- actual reboot tests prove ephemeral and durable state behavior;
- restic is tested by backup, integrity check, destructive source removal,
  restore, comparison, and controlled failure/corruption;
- initrd artifacts and the boot dependency graph are validated without leaking
  private material;
- operational scripts are packaged apps with explicit dependencies, stable
  interfaces, strict checks, and hermetic contract tests;
- custom services have tested, documented systemd hardening and bounded failure
  behavior;
- CI has an explicit job graph, immutable action SHAs, least privilege, fork
  safety, and proportionate public-repository checks;
- every staged gate passes and all mutation tests demonstrate that the new
  checks can fail for the defect they claim to detect;
- physical resilience claims remain marked manual until operator-supervised
  drills produce evidence.
