# CI Pipeline Design

## Goal

Replace the single `nix flake check` CI job with a parallel pipeline that
mirrors the repo's pre-commit workflow, catches build failures before they
reach a host, and provides visibility into closure growth between commits.

## Current state

`.github/workflows/ci.yml` runs a single `nix flake check` step on push/PR to
`main`. This evaluates the flake and checks nixfmt formatting (via
`checks.formatting` from `treefmt-nix`), but does **not**:

- run `deadnix` lint (only in the dev shell)
- build any NixOS configuration
- generate the nix-topology diagram as a CI artifact
- check for accidental plaintext secrets
- compare closure size against the previous build

## Pipeline overview — 4 parallel jobs

```text
Push/PR
  │
  ├─ lint ────────── deadnix + gitleaks
  ├─ eval ────────── nix flake check (formatting + eval)
  ├─ build (matrix) ── nix build + closure diff against last commit
  └─ topology ──────── nix build topology SVG → upload artifact
```

All jobs share the same bootstrap: `actions/checkout@v4`,
`DeterminateSystems/nix-installer-action@v16`, and
`DeterminateSystems/magic-nix-cache-action@v9`.

Jobs are independent — `lint` and `eval` finish quickly, while `build` and
`topology` run longer in parallel.

---

### Job: `lint`

```yaml
lint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: DeterminateSystems/nix-installer-action@v16
    - uses: DeterminateSystems/magic-nix-cache-action@v9
    - run: nix run nixpkgs#deadnix -- --fail
    - run: nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose
```

`deadnix --fail` exits non-zero on unused bindings. `gitleaks --no-git` scans
working-tree files for patterns matching private keys, passwords, API tokens.

---

### Job: `eval`

```yaml
eval:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: DeterminateSystems/nix-installer-action@v16
    - uses: DeterminateSystems/magic-nix-cache-action@v9
    - run: nix flake check
```

Validates flake evaluation and runs all `perSystem` checks (currently
`checks.formatting` from `treefmt-nix` / nixfmt). No build step.

---

### Job: `build`

```yaml
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
```

Key decisions:

- **`--keep-going`**: if one package fails, jobs continue so the full error
  list surfaces in a single run.
- **`matrix.host`**: single element `[soyo]` now; adding a host is
  `[soyo, gazelle]`.
- **Closure cache key**: scoped to host + branch so each branch tracks its own
  baseline. Falls back gracefully (`|| true`) if the previous closure was GC'd
  from the runner.
- **Diff output**: written to `$GITHUB_STEP_SUMMARY` so it appears on the CI
  run page. Example:

  ```text
  nixos-system-soyo-25.05.20250301 → nixos-system-soyo-25.05.20250315
    linux: 6.13.2 → 6.13.5 (+12.3 MiB)
    python3: 3.12.8 → 3.12.9 (+8.1 MiB)
    …12 packages added, 3 removed, 5 changed (+34.2 MiB total)
  ```

---

### Job: `topology`

```yaml
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

Builds the nix-topology diagram and publishes the SVG as a downloadable CI
artifact.

---

### README badge

Update the existing CI badge in `README.md` (line 68 area) to point at the
workflow page with a `?query=branch:main` suffix so it shows the main-branch
status:

```markdown
[![CI](https://github.com/knirski/nix-config/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/knirski/nix-config/actions/workflows/ci.yml)
```

### Files changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Rewrite: 1 job → 4 parallel jobs |
| `README.md` | Update badge URL to include `?branch=main` |
