# Documentation

This is the documentation front door. Start with one intent and follow links
only as detail becomes useful; operational runbooks remain separate from design
history so a planning note is not mistaken for a procedure.

Lifecycle classifications are maintained once in the machine-readable
[`status.json`](status.json). Prominent banners are also kept on documents that
could otherwise be mistaken for current instructions; automated consistency
enforcement belongs to the documentation-check layer.

## Start here

- [Canonical Soyo appliance design](superpowers/specs/soyo-dns-dhcp-appliance.md)
  — decisions, hardware facts, invariants and the M1–M4 roadmap.
- [Guided learning path](learning/README.md) — a code-oriented route through
  Nix, flake-parts, host assembly and each implemented milestone.
- [Design journey](learning/design-journey.md) — why the repository evolved
  toward aspects, thin hosts and declarative recovery.
- [Host role models](learning/host-role-models.md) — alternatives for defining,
  assembling and checking host responsibilities.
- [Shared environment variables](learning/shared-env.md) — broadcast env vars
  across all active terminal sessions.

## Operate

### Install and maintain

- [Install Soyo](install-soyo.md) — canonical live-ISO provisioning runbook.
- [Deploy an existing Soyo](../hosts/soyo/DEPLOY.md) — short index to deployment,
  rollback and recovery procedures.
- [Install zbook](../hosts/zbook/INSTALL.md) — workstation installation notes.
- [Deploy an existing zbook](../hosts/zbook/DEPLOY.md) — short index to
  deployment, rollback and recovery procedures.
- [Install macbook](install-macbook.md) — macbook (nix-darwin) installation runbook.
- [macbook deploy index](../hosts/macbook/INSTALL.md) — macbook deploy pointer.
- [Install ubuntu](install-ubuntu.md) — Ubuntu (standalone Home Manager)
  installation and activation.
- [Set up a workstation](workstation-setup.md) — recommended tooling and CLI setup.
- [Troubleshooting](troubleshooting.md) — common issues and debugging steps.
- [Update and roll back](update-and-rollback.md) — input updates, deployment
  checks and rollback paths.
- [Router recommendations](architecture/router-recommendation.md) — DHCP cutover and router
  capability considerations.

### Protect and recover

- [Secrets](secrets.md) — beginner-oriented agenix-rekey `rekeyFile` workflow.
- [Backup and restore](backup-and-restore.md) — restic restore and btrbk recovery.
- [Recovery](recovery.md) — boot, unlock and break-glass procedures.

## Understand

### Project assessment

- [Project assessment](learning/project-assessment.md) — comprehensive repository review: architecture, invariants, testing pyramid, operational procedures, technical debt, and learning project evaluation.

### Correctness and security

- [Testing and verification](testing.md) — evidence layers, automated checks
  and the manual-verification boundary.
- [Verification layers](learning/verification-layers.md) — a beginner-friendly
  explanation of evaluation, builds, KVM tests, caches and physical drills.
- [Testing baseline](archive/testing-baseline.md) — recorded repository check inventory
  and timing evidence.
- [Public repository data policy](security/public-repository.md) — what the
  public overview may disclose and what remains operator-detailed.
- [Supply-chain policy](security/supply-chain.md) — pinned dependencies,
  workflow trust and distinct credential-scanning boundaries.
- [GitHub security settings](security/github-settings.md) — observed posture
  and separately authorized administrator changes.
- [Service hardening policy](security/service-hardening.md) — reviewed systemd
  privilege, filesystem, network and failure-semantics boundaries.
- [Security reporting](../SECURITY.md) — privately report a vulnerability.

### Subsystem designs

- [LAN observability design](superpowers/specs/2026-07-04-lan-observability-design.md)
- [CI pipeline design](superpowers/specs/2026-07-05-ci-pipeline-design.md)

## Contribute

- [Repository rules](../AGENTS.md) — hard invariants, boundaries, conventions
  and the required validation workflow. Read this before editing.
- [Root README](../README.md) — project scope, safe quick start and architecture.
- [Current correctness and resilience plan](superpowers/plans/2026-07-12-correctness-resilience-docs.md)
  — the active implementation work and task acceptance criteria.
- [Repository gaps and improvements](superpowers/specs/repository-gaps-and-improvements.md)
  — comprehensive gap analysis for hosts, CI, tests, documentation.

### Architecture and topology

- [Architecture documents index](architecture/README.md) — cross-host design docs.
- [Topology diagram guide](topology/README.md) — how the public topology is
  generated, shape legend, and what's deliberately omitted.
- [macOS documentation index](darwin/README.md) — macbook and nix-darwin docs.

Useful entry points in the code:

- `modules/parts/soyo.nix` and `modules/parts/zbook.nix` assemble hosts;
- `modules/nixos/` and `modules/home/` expose opt-in aspects;
- `hosts/` contains hardware and host-specific policy;
- `modules/parts/*check*.nix` and `tests/` contain executable verification.

## Project records

These documents explain earlier decisions or capture completed audits. They are
valuable context, but current code, runbooks and canonical specifications take
precedence. A later status pass may add more precise lifecycle banners without
removing their history.

- [Initial Soyo implementation plan](archive/2026-06-28-soyo-dns-dhcp-appliance.md)
- [LAN observability implementation plan](archive/2026-07-04-lan-observability.md)
- [CI pipeline implementation plan](archive/2026-07-05-ci-pipeline-plan.md)
- [Gap report](archive/gap-report.md)
- [Earlier optional-work plan](archive/optional-work-plan.md)
- [GitHub issue #2 reconciliation](archive/issue-2-reconciliation.md)
- [Superseded Hyprland desktop experiment](archive/hyprland-desktop.md)

## Navigation rules

- Use this page as the primary category index; contextual links elsewhere are
  welcome but should not duplicate whole runbooks.
- Prefer the canonical design for architectural decisions and the runbooks for
  commands.
- Treat dated plans as evidence of intent, not proof of current behavior.
- If documentation and evaluated configuration disagree, stop and investigate
  before operating a host.
