# Repository Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Resolve the repository’s security, CI, portability, source-hygiene, observability, testing, and documentation gaps without live host operations.

**Status:** Completed 2026-08-01 with final review corrections. Hardware deployment, reboot/unlock drills,
and the next upstream command-code dependency release remain explicitly
manual/external follow-ups.

**Architecture:** Keep the existing flake-parts/dendritic structure. Security fixes stay in workflow/package policy files; platform behavior stays in the relevant Home Manager/NixOS aspects; each new guarantee is represented by a pure contract check or fixture-backed test. GitHub branch protection is updated separately through a read-only-then-write API operation.

**Tech Stack:** Nix flakes, flake-parts, NixOS/Home Manager modules, GitHub Actions, Bash, Python, npm lockfiles, OSV-Scanner, and existing NixOS VM/contract checks.

## Global Constraints

- Do not edit `flake.lock` by hand; use `nix flake update <input>` only.
- Do not edit `secrets/rekeyed/` or `hosts/*/facter.json`.
- Do not deploy, reboot, rekey secrets, run a live restore, or alter hardware.
- Preserve tracked `.commandcode/taste/**`; exclude only local `.commandcode/settings.json` and `.claude/**` artifacts.
- Keep Soyo DNS/DHCP roles isolated and preserve existing resource limits.
- For dependency updates, use the repository’s `update-command-code` workflow and verify with OSV plus the built package contract.
- Use `apply_patch` for repository edits.

---

### Task 1: Resolve the vendored npm advisories

**Files:**
- Modify: `modules/_pkgs/command-code-lock/package-lock.json`
- Modify: `modules/_pkgs/command-code.nix` only if the regenerated source hash or npm dependency hash changes
- Modify: `scripts/update-command-code.sh`
- Modify: `docs/security/supply-chain.md`
- Modify: `docs/learning/project-assessment.md`

**Steps:**

- [x] Run the current OSV scan and record the three vulnerable package/version pairs.
- [x] Do not add a repository-local advisory override; dependency remediation belongs in a future upstream `command-code` update.
- [x] Update the lockfile using the repository update workflow; do not hand-edit generated resolution metadata.
- [x] Update `command-code.nix` hashes from the regenerated package build.
- [x] Run the package build, freshness check, and OSV scan; record the remaining upstream advisories without masking them locally.
- [x] Update supply-chain and assessment prose to describe the upstream-update policy and current scan state.

---

### Task 2: Harden PR review workflow and enforce CI at GitHub

**Files:**
- Modify: `.github/workflows/pr-agent.yml`
- Modify: `tests/github-workflows/check_workflows.py` or the relevant workflow-policy fixture/check
- Modify: `docs/security/github-settings.md`
- Modify: `docs/security/supply-chain.md`

**Steps:**

- [x] Keep the PR Agent on the documented `pull_request` trigger without adding `synchronize`; use a base-revision checkout so the tracked `.pr_agent.toml` remains available without checking out the PR head.
- [x] Keep only the comment permissions required by the pinned action and reject broader workflow permissions through the policy checker.
- [x] Run actionlint and workflow-policy tests against the real workflow and fixtures.
- [x] Read back the GitHub ruleset after adding the required static, evaluation, host-build, topology, and resilience contexts.
- [x] Update the security documentation with the actual enforced rule and timestamp.

---

### Task 3: Make local checks tracked-source hermetic

**Files:**
- Modify: `.gitignore`
- Modify: `modules/parts/perSystem.nix`
- Modify: `modules/parts/docs-checks.nix`
- Add or modify: `tests/source-filter/check_source_filter.py` and its flake check

**Steps:**

- [x] Implement one reusable source-filter helper for pre-commit, docs, formatting, and shell checks; it preserves tracked `.commandcode/taste/**` and excludes known checkout artifacts.
- [x] Add `.commandcode/settings.json` and `.claude/` to local ignore policy without ignoring tracked `.commandcode/taste/**`.
- [x] Document the intentional boundary: pure Nix cannot discover Git's tracked-file index, so this is a bounded artifact filter rather than a tracked-file manifest.
- [x] Run the source-filter contract, pre-commit derivation, gitleaks, and docs check.

---

### Task 4: Fix SSH portability and forwarding defaults

**Files:**
- Modify: `modules/home/ssh.nix`
- Modify: `modules/parts/host-role-invariants.nix`
- Modify: relevant SSH documentation in `docs/workstation-setup.md` and `docs/install-ubuntu.md`

**Steps:**

- [x] Add evaluated assertions that GitHub does not force the zbook key on macbook/Ubuntu and that host aliases do not forward the agent by default.
- [x] Remove the hardcoded GitHub `IdentityFile`, retain host-specific identities only where declared, and set `ForwardAgent = false` by default.
- [x] Retain the documented `ssh -A` opt-in pattern for the rare administrative forwarding case.
- [x] Build the affected Home Manager configurations and run host-role invariants.

---

### Task 5: Make healthcheck platform-aware

**Files:**
- Modify: `scripts/healthcheck.sh`
- Modify: `justfile`
- Modify: `tests/scripts/healthcheck.bats`
- Modify: `modules/parts/script-tests.nix`
- Modify: `docs/testing.md` and `docs/workstation-setup.md`

**Steps:**

- [x] Add shell fixtures for macbook and Ubuntu and verify platform probes do not attempt NixOS service or persistence checks.
- [x] Enforce the explicit platform roles and canonical host/role mapping while preserving automatic Soyo/zbook role detection.
- [x] Check platform hostname, Nix installation, Home Manager profile, SSH configuration, and Zsh configuration.
- [x] Make the `just healthcheck` recipe reject unsupported host/platform combinations with an actionable message.
- [x] Run all healthcheck Bats and shell contract checks.

---

### Task 6: Cover Darwin and standalone HM namespaces

**Files:**
- Modify: `modules/parts/perSystem.nix`
- Add or modify: `modules/parts/host-assembler-invariants.nix`
- Modify: `modules/parts/macbook.nix` only if an explicit Darwin aspect assertion is needed
- Modify: `docs/learning/host-role-models.md`

**Steps:**

- [x] Keep namespace declarations checked across NixOS, Darwin, and standalone Home Manager outputs.
- [x] Add evaluated assertions that macbook selects Aerospace rather than Sway and Ubuntu selects Sway rather than Aerospace.
- [x] Run evaluation and the host-role namespace contract.

---

### Task 7: Add observability alert contracts and restore automation

**Files:**
- Modify: `lib/observability/grafana-alert-setup.nix`
- Modify: `modules/parts/observability-contract-checks.nix` or the existing observability check module
- Modify: `modules/parts/backup-integration-check.nix`
- Modify: `docs/backup-and-restore.md`, `docs/testing.md`, and `docs/learning/project-assessment.md`

**Steps:**

- [x] Add Loki and Tempo Prometheus scrape targets before relying on their `up` series.
- [x] Add exact generated-expression contracts for critical scrape, Loki availability, and Tempo availability alerts with conservative `for` windows and existing ntfy routing.
- [x] Keep the existing isolated raw-restic restore integration and the production restore drill manual.
- [x] Run the observability contract, raw restic integration, and backup VM checks where supported.

---

### Task 8: Reconcile lifecycle metadata and flake warnings

**Files:**
- Modify: `docs/status.json`
- Modify: `docs/README.md`
- Modify: `docs/learning/project-assessment.md`
- Modify: `docs/superpowers/plans/2026-07-23-repository-assessment-remediation.md`
- Modify: `modules/parts/deploy.nix` and/or `modules/parts/hm-flake-module.nix` only if required to expose valid standard outputs

**Steps:**

- [x] Mark the remediation plan and design record as completed and keep the documentation index aligned.
- [x] Document `agenix-rekey` and `deploy` as intentional tool-owned namespaces; no duplicate standard aliases are manufactured.
- [x] Run docs checks and `nix flake check --no-build --show-trace`, treating only other unknown-output warnings as regressions.

---

### Task 9: Full verification and handoff

**Files:**
- No source changes unless verification finds a regression.

**Steps:**

- [x] Run `git diff --check` and inspect the complete diff, preserving `.commandcode/settings.json`.
- [x] Run the full static gate, gitleaks, command-code freshness, Linux host builds, Ubuntu build, and non-KVM checks. KVM checks remain unavailable on this runner.
- [x] Read back the GitHub ruleset and confirm required checks.
- [x] Run the final documentation and assessment consistency checks.
- [x] Record the remaining hardware-only, cross-platform-build, and upstream dependency limitations explicitly.
