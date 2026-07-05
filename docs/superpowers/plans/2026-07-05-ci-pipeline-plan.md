# CI Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `nix flake check` CI job with 4 parallel jobs (lint, eval, build+closure-diff, topology) and update the README badge.

**Architecture:** The existing `.github/workflows/ci.yml` is rewritten to a matrix of independent jobs. A `actions/cache` step stores the previous build closure path keyed by host+branch so the next run can diff against it. No Nix module changes — this is pure CI configuration plus a README badge fix.

**Tech Stack:** GitHub Actions, YAML, `nix run nixpkgs#deadnix`, `nix run nixpkgs#gitleaks`, `nix flake check`, `nix build`, `nix store diff-closures`, `actions/cache@v4`, `actions/upload-artifact@v4`, `actions/checkout@v4`, `DeterminateSystems/nix-installer-action@v16`, `DeterminateSystems/magic-nix-cache-action@v9`.

---

## Task 1: Rewrite `ci.yml` — single job → 4 parallel jobs

**Files:**
- Rewrite: `.github/workflows/ci.yml`

- [ ] **Replace the entire workflow content**

Replace `.github/workflows/ci.yml` with:

```yaml
# CI: lint, eval, build, and topology check on every push.
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v16
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - run: nix run nixpkgs#deadnix -- --fail
      - run: nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose

  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v16
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - run: nix flake check

  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        host: [soyo]
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v16
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - run: nix build .#nixosConfigurations.${{ matrix.host }}.config.system.build.toplevel
          --keep-going

      - name: Restore previous closure path
        id: closure-cache
        uses: actions/cache@v4
        with:
          path: previous-closure.txt
          key: closure-${{ matrix.host }}-${{ github.ref_name }}

      - name: Compare closures
        if: steps.closure-cache.outputs.cache-hit == 'true'
        run: |
          PREV=$(cat previous-closure.txt)
          CURR=$(nix path-info result)
          echo "### Closure diff for ${{ matrix.host }}" >> $GITHUB_STEP_SUMMARY
          nix store diff-closures "$PREV" "$CURR" >> $GITHUB_STEP_SUMMARY || true

      - name: Save current closure path
        run: nix path-info result > previous-closure.txt

  topology:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v16
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - run: nix build .#topology.x86_64-linux.config.output
      - run: mkdir -p topology-output && cp result/*.svg topology-output/
      - uses: actions/upload-artifact@v4
        with:
          name: topology
          path: topology-output/
```

- [ ] **Verify flake still evaluates**

```bash
nix flake check
```
Expected: exit 0, no errors.

- [ ] **Verify YAML is well-formed**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```
Expected: exit 0, no syntax errors.

- [ ] **Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: expand to 4 parallel jobs — lint, eval, build+closure-diff, topology"
```

---

### Task 2: Update README CI badge

**Files:**
- Modify: `README.md` (line 68–69 area, the CI section in the Tooling block)

- [ ] **Update the CI badge URL**

The current README has a plain text CI comment (lines 68-69):

```markdown
# CI (runs on every push via GitHub Actions)
# https://github.com/knirski/nix-config/actions
```

No badge currently exists in the README. The Tooling block under the sections is not the badge area. Let me check if there's a badge in the header area (lines 1-9).

Looking at the README, there are badges for NixOS, Flakes, flake-parts, dendritic, nix-topology — but no CI badge. I'll add one in the badge row.

Replace the badge row (lines 3-9) to add a CI badge:

Old:
```html
<p>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white" alt="NixOS"></a>
  <a href="https://nixos.wiki/wiki/Flakes"><img src="https://img.shields.io/badge/flakes-enabled-7eb6e0?logo=nixos&logoColor=white" alt="Flakes"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/built%20with-flake--parts-7eb6e0" alt="flake-parts"></a>
  <a href="https://github.com/vic/import-tree"><img src="https://img.shields.io/badge/pattern-dendritic-7eb6e0" alt="dendritic"></a>
  <a href="https://github.com/oddlama/nix-topology"><img src="https://img.shields.io/badge/diagrams-nix--topology-7eb6e0" alt="nix-topology"></a>
</p>
```

New:
```html
<p>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white" alt="NixOS"></a>
  <a href="https://nixos.wiki/wiki/Flakes"><img src="https://img.shields.io/badge/flakes-enabled-7eb6e0?logo=nixos&logoColor=white" alt="Flakes"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/built%20with-flake--parts-7eb6e0" alt="flake-parts"></a>
  <a href="https://github.com/vic/import-tree"><img src="https://img.shields.io/badge/pattern-dendritic-7eb6e0" alt="dendritic"></a>
  <a href="https://github.com/oddlama/nix-topology"><img src="https://img.shields.io/badge/diagrams-nix--topology-7eb6e0" alt="nix-topology"></a>
  <a href="https://github.com/knirski/nix-config/actions/workflows/ci.yml"><img src="https://github.com/knirski/nix-config/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
</p>
```

- [ ] **Verify formatting**

```bash
nix fmt
```
Expected: no changes (nixfmt only formats `.nix` files, but confirms nothing is broken).

- [ ] **Commit**

```bash
git add README.md
git commit -m "docs(readme): add CI badge to header"
```

---

### Task 3: Update learning docs

**Files:**
- Modify: `docs/learning/README.md` (line 28)

- [ ] **Update the CI pipeline description**

Current (line 28):
```text
| 20 | `.github/workflows/ci.yml`, `modules/nixos/observability.nix` (Grafana alerts) | M2 | CI pipeline, Grafana alerting (disk, backup, service health via ntfy), backup Prometheus metric |
```

Replace with:
```text
| 20 | `.github/workflows/ci.yml`, `modules/nixos/observability.nix` (Grafana alerts) | M2 | CI pipeline (lint → eval → build + closure diff → topology artifact), Grafana alerting (disk, backup, service health via ntfy), backup Prometheus metric |
```

- [ ] **Commit**

```bash
git add docs/learning/README.md
git commit -m "docs(learning): update CI pipeline description"
```
