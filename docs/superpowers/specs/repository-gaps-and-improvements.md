# Plan: Repository gaps and improvements

Status: superseded on 2026-07-22 by the
[Repository Assessment Remediation Plan](../plans/2026-07-23-repository-assessment-remediation.md)

This document is retained as a dated gap-analysis record. Its priorities and
task list are frozen; current remediation ownership and ordering live only in
the replacement plan.

This section note (added 2026-07-23, task D1) reconciles the items below
against the repository as it stands today, without rewriting the frozen
prose itself:

- **Closed since this document was written:** this document's C2 (CI never
  built `darwinConfigurations.macbook`/`homeConfigurations.ubuntu`), H4
  (`just deploy`/`just build-*` didn't cover macbook/ubuntu), H5 (host-role
  invariants didn't cover macbook/ubuntu), and D-C3 (no automated
  link/lifecycle checker) are all done: `.github/workflows/ci.yml` has
  `build-macbook` and `build-ubuntu` jobs, `justfile`'s `deploy`/`build-macbook`/
  `build-ubuntu` recipes exist, `checks.macbook-desktop-invariants` /
  `checks.ubuntu-desktop-invariants` exist, and
  `modules/parts/docs-checks.nix` (`checks.docs-correctness`) is the checker
  this D1 task itself runs. This document's C1 was already resolved (by
  direct `nix eval` verification) at the time this document was written, per
  its own prose above. The 2026-07-23 replacement plan's separately-named H1
  and H2 tasks (different scope than this document's H1/H2 below) closed the
  macbook/ubuntu desktop-binding and runbook *content*-correctness gaps
  (terminal, shell, tool-availability matrix); `docs/workstation-setup.md`'s
  "Planned" labels were replaced with dated "assembler + CI evaluation only;
  hardware deploy pending" status.
- **Still genuinely open as of 2026-07-23:** this document's own H1
  (`modules/darwin/` still has only `base.nix` — no darwin-native `ssh.nix`,
  `tailscale.nix`, or `backup.nix` mirroring the NixOS aspects) and M1
  (`dendritic-options` in `modules/parts/perSystem.nix` still only computes
  `hostOpts` for `soyo`/`zbook`; macbook/ubuntu are not covered). H3 (M4
  guest services) is not a defect at all — the canonical design
  ([`soyo-dns-dhcp-appliance.md`](soyo-dns-dhcp-appliance.md#m4--expansion))
  already records "future services on Soyo" as a deliberate deferral, and
  `AGENTS.md`'s host status table marks Soyo's M4 as "deferred".
- This record is **not** re-annotated item-by-item beyond this note — each
  item below remains historical evidence of what was found on the date this
  document was written, not a live status board. Consult
  [`docs/learning/project-assessment.md`](../../learning/project-assessment.md)
  and the replacement plan for current, dated status.

## Goal

Close the structural and operational gaps identified in the repository
review, in priority order. Each item is sized so it can land in its own PR
(or be deferred cleanly) and ties back to a concrete invariant or doc
section.

This document is descriptive, not prescriptive about ordering — the final
section suggests a PR sequence. Treat items as independent except where
called out.

## Status legend

- **C** — critical (the repo is broken or silently failing on a goal).
- **H** — high-impact (clear value, would land soon in normal work).
- **M** — medium-impact (clear value, but can wait for adjacent work).
- **N** — nice-to-have (housekeeping).

## Critical items

### C1. Register `aspects.darwin.*` namespace the way `aspects.nixos.*` works

**Problem.** The darwin aspect namespace (`aspects.darwin.*`) was initially
suspected of not working because `modules/darwin/base.nix` uses a function
returning a plain value. However, `aspect-options.nix` uses
`lazyAttrsOf lib.types.raw`, which accepts functions as values, so the
existing wiring actually works (`nix eval` confirms `darwinConfigurations.macbook`
evaluates correctly). Two gaps remain from the original analysis:

- **No invariant assertion** that every name in
  `with config.aspects.darwin; […]` resolves to a defined value.
- **No `dendritic-options` coverage** for darwin and HM hosts (see M1).

**Fix.**

1. Add an explicit assertion in `modules/parts/macbook.nix` (or a new
   `modules/parts/host-assembler-invariants.nix`) that every name in
   `with config.aspects.darwin; […]` resolves to a defined value. Fail loudly
   at eval time.
2. Add `dendritic-options` coverage under `modules/parts/perSystem.nix`
   (extend `hostOpts` to include macbook and ubuntu). See also M1.

### C2. CI doesn't build `darwinConfigurations.macbook` or `homeConfigurations.ubuntu`

**Problem.** `tests/github-workflows/` only validates workflow YAML. No
`nix flake check --all-systems` or explicit `.#darwinConfigurations.macbook`
build. "Planned, untested" is the AGENTS.md state — but that also means CI
hasn't caught regressions.

**Fix.**

1. Add a new matrix axis in `.github/workflows/ci.yml` to run
   `nix build path:.#darwinConfigurations.macbook.config.system.build.toplevel`
   on a `macos-latest` runner — `nix-darwin` requires darwin to evaluate
   `aarch64-darwin`. The existing `ubuntu-24.04` runner can build
   `homeConfigurations.ubuntu` standalone.
2. Add a guest-host build check for zbook on every PR touching
   `modules/parts/zbook.nix` or `hosts/zbook/*` — even though it's
   `x86_64-linux`, it can be evaluated today and isn't covered by a
   standalone check (only by `host-role-invariants`).
3. Update AGENTS.md "Status" table from "Planned, untested" to a single
   line that reflects evaluation-only status — don't conflate
   "untested on hardware" with "doesn't evaluate".

**Verification.** New CI job matrix produces green builds.

---

## High-impact items

### H1. macOS aspect coverage mirrors NixOS only in name

**Problem.** `modules/darwin/` has `base.nix` only. `macbook.nix` imports
`config.aspects.homeManager.{base,desktop,ssh,aerospace}` — but the
home-manager darwin mix-ins (e.g. macOS activation, dock defaults,
keyboard) live only in `modules/darwin/base.nix`. There is no
`modules/darwin/{ssh,tailscale,backup}.nix`. Once macbook gets hardware, the
first deploy will discover 20 missing modules.

**Fix.** Treat `modules/darwin/` as the planned parallel of `modules/nixos/`
— write only what's needed right now, but explicitly:

1. `modules/darwin/ssh.nix` — enable `services.openssh` with the same
   host-key posture as `modules/nixos/ssh.nix`.
2. `modules/darwin/tailscale.nix` — Tailscale on macOS uses the GUI app,
   not the systemd service; document the boundary in AGENTS.md
   ("Tailscale on darwin is operator-installed, the aspect only configures
   SSH for tailnet access"), or actually wire a HM-managed install via
   `homebrew`.

**Verification.** macbook CI build (C2) passes with the new aspects.

---

### H2. Ubuntu host directory doesn't exist

**Problem.** `modules/parts/ubuntu.nix` exists; `hosts/ubuntu/` doesn't.
AGENTS.md's "Adding a host" rule says `hosts/<name>/` is required. For
standalone HM the rule is overly strict, but the inconsistency confuses
contributors.

**Fix.** Pick one:

1. Create `hosts/ubuntu/users.nix` mirroring the macbook file (a user
   declaration feels redundant given HM owns it, but the lesson in this
   repo is "host data only, modules do logic", and the standalone-HM case
   needs at least a `home.username`/`home.homeDirectory` declaration
   shape), and document why it's thin.

   **or**

2. Update AGENTS.md "Adding a host → Standalone HM hosts" to say
   explicitly that standalone HM doesn't need a `hosts/<name>/` dir.

Recommendation: update AGENTS.md — adding a placeholder hosts dir just to
satisfy symmetry will look weird. Standalone HM assembles a HM
configuration; the host's "data" is the path it activates against, which
the assembler already encodes.

---

### H3. M4 "guest services" are not implemented

**Problem.** `modules/nixos/` has observability, blocky, dhcp — all
critical-role services (justified by invariant 1). No actual guest service
(Jellyfin, Nextcloud, etc.) has landed. The "Adding a service" workflow
in AGENTS.md is documented but never exercised. Result: when the user does
add one, every rule (resource isolation, reverse proxy, restic class 3)
gets learned at the same time as the service config.

**Fix.** No code change in this repo yet — this is a backlog item. What
lands now:

1. Add a spec under `docs/superpowers/specs/m4-guest-services.md` that
   picks one or two candidate services, drafts the resource-isolation
   numbers against Soyo's 16 GB (per AGENTS.md), and lays out the Caddy
   reverse proxy in front of web services.
2. Wire `lanAppliance.services.reverseProxy` aspect (empty for now, ready
   to populate) so the first service lands with one host-asm change, not a
   template.

**Verification.** Doc PR; no flake change required.

---

### H4. `just deploy` doesn't cover macbook or ubuntu

**Problem.** `justfile` deploy defaults to `soyo`; detection logic only
handles "local NixOS" vs "remote deploy-rs". macbook needs
`darwin-rebuild switch --flake .#macbook`; ubuntu needs
`home-manager switch --flake .#ubuntu`.

**Fix.** Extend `just deploy` so the host-to-system mapping is explicit:

```just
deploy host="soyo":
    @CURRENT="$(hostname -s)" && \
    case "{{host}}" in
      macbook)
        darwin-rebuild switch --flake .#macbook ;;
      ubuntu)
        home-manager switch --flake .#ubuntu ;;
      *)
        if [ "{{host}}" = "$CURRENT" ]; then \
          sudo nixos-rebuild switch --flake .#{{host}}; \
        else \
          nix develop '.#' -c deploy .#{{host}}; \
        fi
        ;;
    esac
```

Add `just build-macbook`, `just build-ubuntu` recipes that mirror the
host system.

**Verification.** `just --list` shows new recipes; the case branch logic
is checked by the existing shellcheck pre-commit hook.

---

### H5. `host-role-invariants` and `soyo-guest-isolation` tests don't cover macbook or ubuntu

**Problem.** `modules/parts/host-role-invariants.nix` only asserts role
boundaries for soyo and zbook. So far OK, but once macbook is real we
need: "macbook doesn't claim appliance role" and the analogous "no GUI on
ubuntu/desktop on soyo" assertions.

**Fix.** Add macbook + ubuntu entries to `testResults` in
`host-role-invariants.nix`. The assertions are cheap; flake-parts evaluates
them anyway.

---

## Medium-impact items

### M1. `dendritic-options` test only covers NixOS hosts

**Problem.** `perSystem.nix` `dendritic-options` computes `hostOpts` only
for `soyo` and `zbook` (NixOS). Macbook (darwin) and ubuntu (HM) never get
the same namespace coverage.

**Fix.** Extend the test to include:

```nix
macbook = [
  # macbook currently imports aspects.darwin.base only.
  # Once we add aspects.darwin.{ssh,tailscale}, this list grows.
];
ubuntu = [
  # aspects.homeManager.{base,desktop,ssh,sway} today.
  # HM aspects register options under their own per-aspect namespace,
  # so we test the HM-aspect option keys exist (e.g.
  # `home-manager.users.krzy.home.<aspect-specific>` paths).
];
```

The existing helper uses `lib.hasAttrByPath` against
`nixosConfigurations.${host}` — add darwin/HM variants that probe
`darwinConfigurations.macbook.config.<path>` and
`homeConfigurations.ubuntu.config.<path>` respectively.

---

### M2. Manual-only verification list is long and could shrink

**Problem.** AGENTS.md lists 9 manual-only checks. Some (initrd SSH, TPM
PCR re-enrollment) genuinely need hardware. Others (restic restore drill,
forced ntfy failure) could be partly covered:

- **restic restore drill:** at least an integration test that the backup
  unit exists and a fresh repo can be initialised — full data restore is
  hard to fake in CI but the unit shape is testable.
- **forced unit failure → ntfy:** sandbox a `systemd-run --unit=test-fail
  sleep 1; exit 1` in the QEMU smoke tests `tests/initrd/` already use.

**Fix.** Add to `tests/initrd/` or a new `tests/notifications/` a QEMU
script that boots a minimal NixOS VM, fails a unit, and asserts the ntfy
endpoint receives a POST (use a stub HTTP server). This pulls in
significantly less than full TPM testing.

---

### M3. Resource-isolation invariant isn't mechanically enforced

**Problem.** Invariant 2 says "every guest service gets MemoryMax,
CPUQuota, and a lowered Nice". `modules/nixos/soyo-guest-isolation.nix`
likely checks known guests — there's no assertion that a *new*
`aspects.nixos.<X>.nix` declaring a service includes those three.

**Fix.** Optional: a `mkGuest` helper in `lib/` that wraps a systemd
service with defaults; requires opt-out for non-guest services. This is
"fence, don't police", matches NixOS style.

---

### M4. Drift between docs and current state

**Problem.** `docs/learning/project-assessment.md` and
`docs/workstation-setup.md` still describe macbook and ubuntu as
"Planned" while assemblers and CI plumbing exist.

**Fix.** Update both to reflect the actual state: assembler + CI exist,
hardware deploy still pending. Keeps the doc in line with the C2 status
table update.

---

### M5. `hosts/zbook/` is 12 files, "thin" rule is at risk

**Problem.** `boot.nix`, `persistence.nix`, `nvidia.nix`, `topology.nix`
in `hosts/zbook/` likely overlap with aspects in `modules/nixos/`. AGENTS.md
says "Keep host directories thin". Once macbook lands it'll duplicate
these.

**Fix.** Audit `hosts/zbook/*` against the existing aspects and lift
what's reusable. Don't refactor speculatively — wait for macbook to need
the same modules, then promote. Specifically: `hosts/zbook/nvidia.nix`
could become `aspects.nixos.nvidia` (already does in spirit) and
`hosts/zbook/topology.nix` is data, fine to keep.

---

## Documentation gaps and improvements

This section extends the existing plan with documentation-only items. Inherits
the same status legend (C/H/M/N) but the items here are doc PRs — small,
mechanical, and convertible to many of the spec-level changes in the active
correctness plan (`docs/superpowers/plans/2026-07-12-correctness-resilience-docs.md`).

### D-C1. `docs/workstation-setup.md` still labels macbook and ubuntu as "Planned"

**Problem.** README.md's host table lists only soyo and zbook as "Production",
but `docs/workstation-setup.md:26-34` describes macbook and ubuntu as
"Planned" with "Planned" sit-atop the availability matrix. The assemblers and
`justfile` recipes exist; the docs are out of step.

**Fix.**

1. Re-label both hosts to "Assembler + CI evaluation only; hardware deploy
   pending." Mirror the AGENTS.md "Status" style after C2 lands.
2. Drop the "Planned" decorative headings; keep the section content but
   note that deploying requires hardware access and that the matrix is the
   intended target state, not the current state.

**Verification.** Grep `docs/` for "Planned" matched against macbook/ubuntu;
expect zero hits after the change.

---

### D-C2. `hosts/zbook/INSTALL.md` keeps historical COSMIC debug text in the main flow

**Problem.** Lines 4, 119–137 of `INSTALL.md` describe COSMIC-specific DRM
master / SIGSTOP/SIGCONT workarounds under a "Historical" banner but still in
the runbook body. The active plan (T2) lists this as open work.

**Fix.** Move the COSMIC historical narrative to a comment in
`modules/nixos/nvidia.nix` (or a `docs/archive/zbook-history.md` entry) and
replace `INSTALL.md`'s "Post-install gotchas" with the *current* gotchas
only — s2idle, USB-C dock wake, Logitech receiver. Keep one short pointer
to the archive explaining where the COSMIC context lives now.

**Verification.** Grep `docs/` for "COSMIC" — only `archive/` and inline code
comments should match.

---

### D-C3. No automated internal-link / orphan / status-consistency check

**Problem.** `docs/README.md` references `hosts/soyo/DEPLOY.md` and
`hosts/zbook/INSTALL.md`; both exist, but link breakage isn't checked.
`docs/status.json` declares lifecycle roles and replacements; nothing
enforces "no canonical doc has status=superseded" or "every entry has a
matching file".

**Fix.** Add a new test module `modules/parts/docs-checks.nix` (probably
already exists — verify and extend) that walks `docs/**/*.md`, parses
markdown links, and asserts each link resolves either to an existing file
or to an absolute URL. Cross-check `status.json` entries against the file
tree. Wire into `nix flake check`.

**Verification.** `just check` runs the new check; intentional link removal
is the failure case, expected to catch the link rot.

---

### D-H1. No macOS / nix-darwin install runbook

**Problem.** `docs/install-soyo.md` and `hosts/zbook/INSTALL.md` cover the
two deployed NixOS hosts. The macbook assembler is real but has no install
runbook; the only doc reference is a TODO pointing at
`~/.commandcode/plans/add-macbook-nix-darwin.md` which is outside the repo.

**Fix.** Create `docs/install-macbook.md` (canonical runbook) and
`hosts/macbook/INSTALL.md` (thin pointer, mirrors `hosts/soyo/DEPLOY.md`'s
pattern). Cover: bootstrap from a stock macOS, install Nix (determinate
installer), clone repo, register host key, rekey secrets, first
`darwin-rebuild switch`, validation steps. Note that the macbook agenix
path is gated on hardware — the runbook can land as "ready" but will only
be exercised post-C1/C2.

---

### D-H2. No Ubuntu standalone-HM install runbook

**Problem.** Ubuntu uses `home-manager switch --flake .#ubuntu`. No
bootstrap runbook; `docs/workstation-setup.md:34` says "Planned" and stops.

**Fix.** Create `docs/install-ubuntu.md` with: enable Nix on Ubuntu 24.04
(Determinate installer or `nix-env` from tarball), clone repo, register
host key, rekey secrets (`secrets/ubuntu.pub` is needed; create that file
via SSH key on the host), first activation. Standalone HM doesn't own
disko/boot/persistence, so the runbook is short. Add `hosts/ubuntu/`
directory only if you decide it carries host data; otherwise document the
deliberate absence (see H2).

---

### D-H3. No "what to do when `just check` / CI is red" troubleshooting

**Problem.** `just check` and the CI matrix are the operator's daily gate.
Neither `docs/troubleshooting.md` nor `AGENTS.md` Workflow section walks
through reading a CI failure log, narrowing from `nix flake check --keep-going`
output to a single failed check, and reading the derivation's stdout.

**Fix.** Add a "Reading a failed check" subsection to `docs/troubleshooting.md`
(or a dedicated `docs/reading-ci-failures.md`). Walk through one real or
synthetic failure: which output lines map to which tier (static → eval →
build → KVM), how to re-run a single check (`nix build path:.#checks.<arch>.<check>`),
where hermetic output differs from remote CI (no `/dev/kvm`, no
`secrets/rekeyed/<host>`).

---

### D-H4. No per-host runbook for `hosts/zbook/`

**Problem.** Soyo has both `hosts/soyo/DEPLOY.md` (pointer) and
`docs/install-soyo.md` (canonical). zbook only has `INSTALL.md`. A reader
looking for "deploy an existing zbook" lands on install guidance.

**Fix.** Add `hosts/zbook/DEPLOY.md` matching `hosts/soyo/DEPLOY.md`'s
shape: pointer to `docs/update-and-rollback.md` for routine deploys, to
`docs/recovery.md` for break-glass, and to `just healthcheck zbook` for
verification.

---

### D-H5. No index of `modules/parts/*check*.nix`

**Problem.** Multiple per-check modules exist (`backup-integration-check`,
`dns-dhcp-checks`, `topology-checks`, `host-role-invariants`,
`soyo-guest-isolation`, `systemd-hardening-checks`, …). `docs/testing.md`
names evidence classes but doesn't enumerate what each check asserts.
New contributors can't tell which check covers what.

**Fix.** Add a "Named checks" section to `docs/testing.md`: for each
`modules/parts/*check*.nix`, list the assertion set in one line. Maintain
this as the canonical index — the alternative is letting someone grep.

---

### D-H6. No "adding a check" guide

**Problem.** The pattern (assertion module + CI hookup + KVM-free
evaluation) is mature and repeated, but only documented implicitly.

**Fix.** Add `docs/dev/adding-a-check.md` (or `docs/learning/adding-a-check.md`
if you prefer the learning-track location): walk through writing one new
assertion, registering it under `perSystem.checks.<arch>`, observing it
fail and pass, and the difference between pure-eval checks and KVM-requiring
behavior tests. Pair it with D-H5.

---

### D-M1. `docs/secrets.md` is 27.5 KB / 700+ lines

**Problem.** Largest doc in the repo. It tries to be both a beginner
walkthrough and a complete reference for rotation/recovery. Risk:
rekey-flow changes force editing one unwieldy file; new operators see a
wall of text.

**Fix.** Split into:

- `docs/secrets.md` — overview, threat model, file layout (keep current
  frontmatter and TOC).
- `docs/secrets/daily-operations.md` — edit / add / rotate, with worked
  examples pulled from current §Daily operations.
- `docs/secrets/key-rotation.md` — rotate the master key, rotate a host
  key, recovery from history.
- `docs/secrets/bootstrap.md` — first install without a known host key.

Update `docs/README.md` "Operate" section to link each individually. This
is a doc-only refactor; the markdown content is reorganised, not rewritten.

---

### D-M2. No "documents map" visual or markdown table

**Problem.** `docs/README.md`'s prose categorisation works but a quick
reference table would help onboarding. A reader landing in the repo needs
to learn the rulebook → design → runbook → history distinction.

**Fix.** Add a one-screen `docs/MAP.md` (or top of `docs/README.md`):

```text
Hard rules            → AGENTS.md
Architecture & why    → superpowers/specs/
Operate (runbooks)    → install-soyo.md, recovery.md, secrets.md, …
Tutorial & motivation → learning/
Plan & progress       → superpowers/plans/2026-07-12-…
Historical records    → archive/  (treat as evidence of intent)
```

---

### D-M3. Last-updated / freshness footers

**Problem.** A reader can't tell when a doc was last meaningful without
`git log`. `status.json` has lifecycle but no `lastReviewed` date.

**Fix.** Two complementary changes:

1. Add `lastReviewed` field to `status.json` schema, mechanically derived
   from `git log -1 --format=%ad` per file, exposed as a generation script
   (`just docs-status`).
2. Optional doc footer line `<!-- last reviewed: YYYY-MM-DD -->` rendered
   into the served HTML by a future step (not necessary now; status.json
   is the source of truth).

---

### D-M4. `docs/topology/overview.svg` has no companion README

**Problem.** README.md embeds the SVG. `docs/security/public-repository.md`
explains the redaction policy. Nothing explains: how to regenerate the SVG,
what each shape/colour means, what is deliberately omitted.

**Fix.** Add `docs/topology/README.md` covering: generation command
(`just topology`), input files consumed by `modules/parts/topology.nix`,
shape legend, sanitization rules, and a deliberate list of what's *not*
shown (per the public-data policy cross-link).

---

### D-M5. `docs/router-recommendation.md` sits oddly

**Problem.** It's implementation-flavored network advice, but currently
sits next to runbooks in `docs/`. Either it should sit with
`docs/topology/` (it's an upstream-network design doc), or under a
`docs/architecture/` bucket that absorbs related material.

**Fix.** Either:

1. Move `docs/router-recommendation.md` → `docs/topology/router-recommendation.md`
   and update `docs/README.md` links.
2. Create `docs/architecture/README.md` for cross-host design docs
   (router, observability design already in `superpowers/specs/`,
   topology diagrams in `docs/topology/`).

Recommendation: option 2 — `docs/architecture/` becomes a one-stop
"how the hosts fit together" view separate from host-specific runbooks
and from per-subsystem specs.

---

### D-M6. `justfile` recipes lack uniform `--list` doc

**Problem.** `just --list` shows terse descriptions. A few recipes
(`build`, `deploy`, `healthcheck`) have inline comments; others
(`test-resilience`, `topology`, `topology-operator-detailed`) don't. The
"browse-by-justfile" UX is uneven.

**Fix.** Add a `#` comment line above every recipe summarising:
- what it does (one sentence)
- prerequisites (`KVM?`, `darwin runner?`, `sudo?`)

Pattern matches existing well-commented recipes. No CLI change.

---

### D-N1. No `docs/darwin/` subdirectory

**Problem.** `modules/darwin/` exists, the macbook assembler exists, but
no doc. Either create one or document the omission.

**Fix.** Land `docs/install-macbook.md` (D-H1) first; once it lands,
add a one-page `docs/darwin/README.md` that points at it, summarizes
cross-platform parity goals, and explains "macbook aspects live next to
NixOS aspects, not on a separate page".

---

### D-N2. SECRETS.md cross-link from root

**Problem.** README.md mentions `SECURITY.md` but I didn't verify it
points at `docs/security/{public-repository.md, supply-chain.md}`. If
a vulnerability report lands on `SECURITY.md` alone, it doesn't surface
the operational policy docs.

**Fix.** Read `SECURITY.md` (out of scope this turn). If it doesn't
cross-link, add a "See also" section pointing at the relevant
`docs/security/` documents. Mechanical verification.

---

## Nice-to-have items

### N1. `lib/systemd-hardening.nix` is module-shaped

**Problem.** Lives under `lib/` but looks like a module helper. AGENTS.md
says "reusable non-module helpers under lib/". Borderline.

**Fix.** Either: rename `lib/` to use explicit sub-dirs
(`lib/aspects/`, `lib/observability/`, `lib/topology/`) and document them,
or move `systemd-hardening.nix` to `modules/_pkgs/` (next to other
module helpers). Strict rule aids navigation.

---

### N2. README doesn't surface the learning docs

**Problem.** Repo has `README.md` (unverified) but `AGENTS.md` is the
rulebook; the dependency is invisible at the root.

**Fix.** If the README is sparse, replace or extend it with a 10-line
pointer: "Start with `AGENTS.md` (the rulebook) and
`docs/superpowers/specs/soyo-dns-dhcp-appliance.md` (the why)."

---

### N3. Renovate coverage for DMS family

**Problem.** `flake.nix` lists 6 DMS-related inputs; whether Renovate
tracks them is unclear.

**Fix.** Read `renovate.json`; if `nixdInputs` only includes the major
inputs (`nixpkgs`, `home-manager`, etc.), add the DMS family explicitly
under a less-restrictive match pattern (these update more often and
break more often).

---

## Suggested PR sequence

To land these without coupling:

1. **PR 1 (Critical):** C1 fix only (aspects.darwin namespace + base
   refactor + invariant assertion). Smallest, highest-value. Standalone.
2. **PR 2 (Critical):** C2 macOS + HM CI matrix addition. Requires C1 so
   the macbook build doesn't break.
3. **PR 3 (High):** H4 `just deploy` cases. Standalone, mechanical.
4. **PR 4 (High):** H1 darwin SSH/tailscale skeleton. Builds on C1.
5. **PR 5 (High):** H2 AGENTS.md clarification (no `hosts/ubuntu/`
   needed). Trivial.
6. **PR 6 (High):** H5 + M1 `host-role-invariants` and
   `dendritic-options` extensions. Lands macbook/ubuntu entries.
7. **PR 7 (Medium):** M4 doc sync. Brings docs into line with reality.
8. **PR 8 (Medium):** H3 spec for first guest service (no flake change).
9. **PR 9 (Nice):** M5 zbook host-dir slim-down, M2 initrd/notification
   smoke test scaffolding, N1 lib refactor, N3 renovate tweak. Each can
   be its own commit.

What this repo *needs* before users actually get value: items C1, C2, H4
land together turn the macbook assembler from a silent failure into a CI
signal — the rest is housekeeping.

### Doc PR sequence

Doc-only items (the D-prefixed section above) land independently of the
code PRs above. They can run in parallel — none change `flake.nix` and
none will break `just check`. The doc CI checks added by D-C3 should land
before PR D-7 (which restructures `docs/secrets.md`) so broken links surface
in CI rather than during review.

1. **PR D-1 (Critical):** D-C1 (relabel macbook/ubuntu in
   `workstation-setup.md`) + D-C2 (move COSMIC historical text out of
   `INSTALL.md`). Smallest, quickest fixes for actively-wrong docs. One
   PR.
2. **PR D-2 (Critical):** D-C3 internal-link and orphan check. Wired
   into `nix flake check`. May surface other broken links, which feed
   into doc-only fixes.
3. **PR D-3 (High):** D-H1 + D-H2 macbook and ubuntu install runbooks.
   Pure doc.
4. **PR D-4 (High):** D-H3 troubleshooting — "Reading a failed check".
5. **PR D-5 (High):** D-H4 `hosts/zbook/DEPLOY.md` pointer, matching
   Soyo. About ten lines.
6. **PR D-6 (High):** D-H5 + D-H6 — check index and "adding a check"
   guide.
7. **PR D-7 (Medium):** D-M1 secrets.md split. Single biggest single-doc
   refactor; review carefully.
8. **PR D-8 (Medium):** D-M2 docs map (table or short page).
9. **PR D-9 (Medium):** D-M3 freshness footer (status.json field +
   generation script).
10. **PR D-10 (Medium):** D-M4 + D-M5 topology README + router doc
    reorganisation.
11. **PR D-11 (Nice):** D-M6 justfile uniform doc comments.
12. **PR D-12 (Nice):** D-N1, D-N2 — darwin docs index, SECURITY.md
    cross-links.

What ships first is largely independent. The high-leverage starter is
**PR D-1** — actively wrong docs, trivial to fix, instant payoff.

## Out of scope (call out explicitly)

- macbook hardware testing: depends on the device, not the repo.
- Deploy-rs for macbook: requires `aarch64-darwin` nix-darwin activation
  chain — design choice the user should make (H1 dependency).
- Standalone-HM flake-parts module shape (`hm-flake-module.nix`): the
  existing convention works for one host; generalize when there's a second
  standalone HM host.
- macbook Tailscale install: a doc gap (no runbook section on the
  GUI-managed install path); out of scope here, add as a follow-up doc
  item when D-H1 lands.
