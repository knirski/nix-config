# Repository Gap and Improvement Report

> **Status: Historical.** This audit drove the completed gap-remediation pass.
> Its observations and task prompts are preserved as evidence; use
> [testing.md](../testing.md) and the current code for present behavior.

Status refreshed after the Home Manager fix.

## Current verified state

- Working tree is clean.
- `home.stateVersion` is now `26.05`.
- `nix flake check --no-build` passes.
- Both NixOS configurations evaluate:
  - `nixosConfigurations.soyo`
  - `nixosConfigurations.zbook`
- Deploy-rs checks evaluate.
- Remaining evaluation warnings:
  - unknown flake output `agenix-rekey`
  - unknown flake output `deploy`
  - deprecated `system` usage, replaced by `stdenv.hostPlatform.system`
- Full derivation builds and live-host health checks were not run during this audit.

The repository is structurally strong. The main remaining weaknesses are documentation drift, limited behavioral testing of critical services, duplicated validation logic, and insufficient machine-checkable enforcement of architectural invariants.

---

## Instructions for implementation agents

Each task below is intentionally bounded so a smaller model can execute it independently.

Before changing anything:

1. Read [AGENTS.md](../../AGENTS.md).
2. Read the files listed under the task.
3. Do not modify:
   - `flake.lock` manually
   - `secrets/rekeyed/`
   - `hosts/*/facter.json`
   - encrypted `.age` contents
4. Preserve unrelated user changes.
5. Use `apply_patch` for edits.
6. Format changed Nix files with the repository formatter.
7. Run the task-specific checks.
8. Use a conventional commit message without a period if asked to commit.
9. Do not deploy or contact live hosts unless explicitly instructed.

Recommended execution order:

1. T1 — reconcile canonical architecture documentation
2. T2 — reconcile zbook desktop/NVIDIA documentation
3. T3 — fix lint/check duplication
4. T4 — add reservation validation
5. T5 — add DNS/DHCP evaluation tests
6. T6 — enforce guest-service isolation
7. T7 — validate persistence invariants
8. T8 — consolidate Soyo installation docs
9. T9 — improve rekey identity portability
10. T10 — investigate harmless flake warnings

---

## T1 — Reconcile the canonical architecture with `import-tree`

Priority: High
Type: Documentation/design decision
Risk: Low if documentation-only

### T1 Problem

The implementation uses `vic/import-tree` to automatically import every applicable file under `modules/`, but the hard invariant and canonical design originally described a manual module registry.

There is no `modules/default.nix`.

Conflicting sources:

- [AGENTS.md](../../AGENTS.md)
- [canonical design](../superpowers/specs/soyo-dns-dhcp-appliance.md)
- [learning README](../learning/README.md)
- [design journey](../learning/design-journey.md)

Current implementation:

- [flake.nix](../../flake.nix)

### T1 Required decision

Treat the current `import-tree` implementation as authoritative unless the user explicitly asks to restore an explicit registry.

Do not create `modules/default.nix` merely to satisfy stale prose.

### T1 Changes

Update the documentation to state:

- `flake.nix` calls `inputs.import-tree ./modules`.
- Eligible `.nix` files are automatically imported.
- `_`-prefixed paths such as `modules/_pkgs/` are excluded.
- Host assemblers still opt into aspects explicitly.
- Auto-importing a file does not automatically enable its NixOS behavior.
- Reusable non-module Nix helpers must live outside the imported tree, currently under `lib/`.
- Adding an aspect requires:
  1. creating the aspect file;
  2. exposing `aspects.nixos.<name>` or `aspects.homeManager.<name>`;
  3. toggling it in the appropriate host assembler.

Update the hard invariant so it describes the actual mechanism.

### T1 Acceptance criteria

```bash
test ! -e modules/default.nix
rg -n --glob '!docs/gap-report.md' \
  'modules/default\.nix.*explicit|explicitly lists every' \
  AGENTS.md README.md docs flake.nix
```

The second command should produce no stale claims.

Then run:

```bash
nix flake check --no-build
```

Expected result: success, aside from already-known warnings.

### T1 Suggested commit

```text
docs(architecture): align dendritic docs with import-tree
```

---

## T2 — Reconcile COSMIC, Sway, DMS, and NVIDIA documentation

Priority: High
Type: Documentation plus possible regression investigation
Risk: Medium

### T2 Problem

The repository documents `modules/nixos/cosmic.nix`, but the file does not exist. The active zbook assembler enables `sway`, and the current desktop uses Dank Material Shell.

Stale references include:

- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
- [learning README](../learning/README.md)
- [learning README](../learning/README.md)

Current code:

- [zbook assembler](../../modules/parts/zbook.nix)
- [NixOS Sway aspect](../../modules/nixos/sway.nix)
- [Home Manager Sway aspect](../../modules/home/sway.nix)
- [NVIDIA aspect](../../modules/nixos/nvidia.nix)

### T2 Important caution

Do not simply replace every `cosmic.nix` string with `sway.nix`.

Some text describes a specific historical workaround:

- SIGSTOP/SIGCONT of `cosmic-comp`
- `nvidia-suspend.service` ordering
- dock re-enumeration delay
- display re-probe after resume

First determine whether that workaround:

1. moved to another file;
2. became unnecessary after switching compositors;
3. was accidentally removed;
4. still describes the live machine despite no matching declarative code.

Use Git history if needed:

```bash
git log --all -- modules/nixos/cosmic.nix
git log -S'cosmic-comp' --all --oneline
git log -S'ExecStartPre' --all -- modules/nixos
```

### T2 Changes

After determining the current truth:

- Correct the README module tree.
- Correct the learning path.
- Correct AGENTS.md known issues.
- Mark obsolete workarounds as historical if they are no longer active.
- Do not claim a workaround is implemented unless matching code exists.
- Ensure the health check’s workstation service check matches the actual greeter service.

Relevant health-check location:

- [scripts/healthcheck.sh](../../scripts/healthcheck.sh)

### T2 Acceptance criteria

Either:

```bash
test -f modules/nixos/cosmic.nix
```

or:

```bash
! rg -n 'modules/nixos/cosmic\.nix' AGENTS.md README.md docs
```

Also verify documented enabled aspects match the assembler:

```bash
sed -n '1,120p' modules/parts/zbook.nix
```

Run:

```bash
nix flake check --no-build
nix run nixpkgs#markdownlint-cli -- \
  --disable MD013 MD033 MD060 MD029 MD031 MD032 \
  --ignore .commandcode '*.md' 'docs/**/*.md'
```

### T2 Suggested commit

```text
docs(zbook): align desktop guidance with current sway setup
```

---

## T3 — Make linting consistent across hooks, `just`, and CI

Priority: Medium-high
Type: Tooling
Risk: Low

### T3 Problem

Lint definitions are duplicated across:

- [modules/parts/perSystem.nix](../../modules/parts/perSystem.nix)
- [justfile](../../justfile)
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml)

The copies are already inconsistent. ShellCheck is explicitly run only against:

```text
scripts/healthcheck.sh
```

Other tracked shell scripts are omitted from explicit CI and `just lint` commands:

- `scripts/recover-secrets.sh`
- `scripts/set-tailscale-keys.sh`

The generated pre-commit check may still find them, but the manually duplicated commands obscure which check is canonical.

### T3 Desired outcome

Use one canonical lint definition wherever practical.

Preferred model:

- `pre-commit.settings` remains the source of hook configuration.
- `nix flake check` runs the generated pre-commit derivation.
- CI runs `nix flake check`.
- `just lint` invokes the generated check or a single shared command rather than recreating every tool configuration.

If keeping explicit CI steps for clearer logs, ensure their file coverage and options exactly match the hook definitions.

### T3 Changes

At minimum:

- Include all tracked shell scripts in ShellCheck.
- Ensure Ruff covers both Python files.
- Ensure Markdownlint exclusions match in all locations.
- Ensure gitleaks behavior is intentionally different:
  - pre-commit: staged changes;
  - CI: entire checkout.
- Document that difference in one concise comment.

Possible robust ShellCheck invocation:

```bash
git ls-files '*.sh' -z | xargs -0 shellcheck
```

Be careful with Nix derivations and empty input lists. There are currently shell files, so this repository is not empty.

### T3 Acceptance criteria

```bash
git ls-files '*.sh'
```

All listed files must be checked by the canonical lint path.

Then:

```bash
just lint
nix flake check --no-build
```

If cheap enough, also run:

```bash
nix flake check
```

### T3 Suggested commit

```text
ci(lint): unify repository lint coverage
```

---

## T4 — Validate reservation data at evaluation time

Priority: High
Type: Correctness test
Risk: Low

### T4 Problem

[hosts/soyo/reservations.nix](../../hosts/soyo/reservations.nix) is the critical single source of truth for:

- DHCP assignments
- forward DNS
- reverse DNS
- topology
- observability metadata

There is no strong validation visible for duplicate or malformed entries. A typo could create conflicting DHCP assignments or invalid generated records.

### T4 Required validations

At minimum, reject:

- repeated names are allowed intentionally for multihomed hosts and multi-A
  records, but each entry must still have a unique MAC and IP address;
- duplicate MAC addresses;
- duplicate IP addresses;
- invalid IPv4 strings;
- invalid MAC strings;
- names unsuitable for the local DNS label policy;
- reserved addresses outside the intended LAN subnet;
- reservations overlapping the dynamic DHCP pool, unless the design explicitly permits it.

Normalize MAC comparison to lowercase before duplicate detection.

Do not silently repair data. Fail evaluation with a clear message identifying the offending value.

### T4 Implementation options

Preferred:

- Create a small reusable validation function outside the import-tree scope, for example under `lib/`.
- Call it from the DHCP/DNS host configuration or assembler.
- Add pure evaluation tests under `checks`.

Avoid putting a plain helper `.nix` under `modules/` because `import-tree` may treat it as a flake-parts module.

### T4 Tests

Include positive and negative cases:

- current reservation list passes;
- repeated name with distinct MAC and IP values passes;
- duplicate MAC with different case fails;
- duplicate IP fails;
- malformed MAC fails;
- malformed IPv4 fails;
- invalid DNS label fails.

Tests should not require a VM.

### T4 Acceptance criteria

```bash
nix flake check --no-build
nix build .#checks.x86_64-linux.<new-check-name> --no-link
```

The current production reservation list must pass unchanged unless a real data error is discovered.

### T4 Suggested commit

```text
test(network): validate reservation data invariants
```

---

## T5 — Add DNS/DHCP behavioral evaluation tests

Priority: High
Type: Critical-role testing
Risk: Medium

### T5 Problem

DNS and DHCP are the only critical Soyo roles, but current repository-specific tests mainly cover:

- aspect option presence;
- LAN inventory Python behavior;
- general Nix evaluation/builds.

There is no focused test proving that the reservation source generates consistent Blocky and dnsmasq configuration.

### T5 Phase 1: evaluation tests

Start with evaluation tests rather than a full VM test.

Verify:

- every reservation produces the expected forward A record;
- every reservation produces the expected dnsmasq DHCP host mapping;
- dnsmasq remains responsible for lease-aware PTR records;
- Blocky forwards the reverse zone to dnsmasq;
- Blocky and dnsmasq bind compatible addresses/ports;
- expected domain is `home.arpa`;
- Soyo’s own forward and reverse records are consistent;
- DHCP advertises the intended DNS server and search domain;
- the router remains the default gateway.

Prefer checking evaluated configuration values rather than rendered text when NixOS exposes structured options.

### T5 Phase 2: NixOS VM test

Only after the evaluation tests are stable, consider a VM integration test that starts Blocky and dnsmasq on an isolated virtual network.

Possible assertions:

- `dig` resolves a reservation through Blocky;
- reverse lookup reaches dnsmasq;
- blocked domain returns the configured blocked response;
- dnsmasq starts without port conflicts;
- service restart preserves the lease file when backed by a persistent test mount.

Keep the first VM test narrow. Do not attempt to reproduce TPM or Secure Boot in it.

### T5 Acceptance criteria

Phase 1:

```bash
nix build .#checks.x86_64-linux.dns-dhcp-config --no-link
nix flake check --no-build
```

Phase 2, if implemented:

```bash
nix build .#checks.x86_64-linux.dns-dhcp-vm --no-link
```

### T5 Suggested commits

```text
test(soyo): verify generated DNS and DHCP configuration
```

Optional second commit:

```text
test(soyo): add DNS and DHCP integration VM
```

---

## T6 — Enforce resource isolation for Soyo guest services

Priority: High
Type: Architectural invariant enforcement
Risk: Medium

### T6 Problem

AGENTS.md requires every guest service on Soyo to have:

- `MemoryMax`
- `CPUQuota`
- lowered scheduling priority through `Nice` or `IOWeight`

Many observability and auxiliary services do set limits, but the invariant is enforced by review rather than a comprehensive machine-readable check.

### T6 Scope

Audit enabled Soyo services that are not DNS or DHCP.

Likely guest or auxiliary services include:

- Grafana
- Prometheus
- Loki
- Tempo
- Alloy
- exporters
- LAN inventory collector
- alert setup units
- restic helper units
- Tailscale authentication helper
- maintenance helper units

Do not classify critical operating-system units as guest services.

Clarify whether Blocky and dnsmasq are exempt because they are the two critical roles. Their reliability tuning may differ from guest throttling.

### T6 Desired implementation

Add a flake check that evaluates the Soyo configuration and verifies an explicit list of guest units.

For every listed unit, require:

- non-null/non-infinite memory cap;
- CPU quota;
- `Nice > 0` or deliberately lowered `IOWeight`;
- no accidental elevated scheduling priority.

Use an explicit guest-unit inventory. Do not heuristically classify every systemd unit.

The explicit inventory makes additions reviewable and avoids false positives from NixOS-generated infrastructure units.

### T6 Acceptance criteria

The test must fail if one audited unit has its `MemoryMax` removed.

Normal verification:

```bash
nix build .#checks.x86_64-linux.soyo-guest-isolation --no-link
nix flake check --no-build
```

Update AGENTS.md only if the exact interpretation of “lowered Nice/IOWeight” needs clarification.

### T6 Suggested commit

```text
test(soyo): enforce guest service resource limits
```

---

## T7 — Add persistence and backup consistency checks

Priority: High
Type: Impermanence correctness
Risk: Medium

### T7 Problem

With a wiped root, missing persistence is an operational failure. Current inventories are readable, but there is no automated check connecting:

- enabled stateful services;
- preservation entries;
- backup paths;
- early-boot requirements.

Relevant files:

- [shared persistence module](../../modules/nixos/persistence.nix)
- [Soyo inventory](../../hosts/soyo/persistence.nix)
- [zbook inventory](../../hosts/zbook/persistence.nix)
- [backup module](../../modules/nixos/backup.nix)
- [Soyo backup data](../../hosts/soyo/backup.nix)
- [zbook backup data](../../hosts/zbook/backup.nix)

### T7 Required checks

For both hosts:

- `/persist` is available during early boot where required.
- `/etc/ssh` is persisted and available in initrd.
- `/etc/machine-id` is persisted and available in initrd.
- agenix identity paths refer to persisted host keys.
- `/var/lib/nixos` is persisted.
- Tailscale state is persisted.
- restic SSH material under `/etc/restic` is persisted.

For Soyo:

- dnsmasq leases are persisted;
- Grafana state is persisted;
- Prometheus state is persisted;
- Loki state is persisted;
- Tempo state is persisted;
- Alloy journal cursor/state is persisted;
- sbctl keys are persisted;
- persisted service state is covered by the intended backup class.

For zbook:

- sbctl keys are persisted;
- user data declared durable is backed up according to policy;
- large caches are persisted only deliberately;
- overlapping entries such as `Pictures` and `Pictures/Screenshots` do not create ambiguous preservation behavior.

### T7 Design caution

Do not assume that every persisted directory belongs in restic. Some state may be:

- reproducible;
- disposable cache;
- too large;
- covered by a different backup policy.

Encode explicit expectations rather than asserting “all persistence must be backed up.”

### T7 Acceptance criteria

```bash
nix build .#checks.x86_64-linux.persistence-invariants --no-link
nix flake check --no-build
```

Document any deliberately persisted-but-not-backed-up directory.

### T7 Suggested commit

```text
test(persistence): verify durable state inventories
```

---

## T8 — Consolidate Soyo installation documentation

Priority: Medium
Type: Documentation safety
Risk: Low

### T8 Problem

Soyo installation guidance is duplicated between:

- [docs/install-soyo.md](../install-soyo.md)
- [hosts/soyo/DEPLOY.md](../../hosts/soyo/DEPLOY.md)

Both cover sensitive operational steps involving:

- operator SSH keys;
- placeholder host public keys;
- agenix rekeying;
- TPM enrollment;
- first deployment.

Duplication increases the chance that one procedure becomes unsafe or incomplete.

### T8 Desired result

Make `docs/install-soyo.md` canonical.

Reduce `hosts/soyo/DEPLOY.md` to either:

- a short host-specific checklist linking to the canonical runbook; or
- remove it if it contains no unique information.

Do not remove unique recovery details without relocating them.

### T8 Required structure for canonical runbook

The canonical document should clearly separate:

1. prerequisites;
2. live ISO preparation;
3. host SSH key generation;
4. replacement of any placeholder public key;
5. `agenix rekey`;
6. disk installation;
7. first boot;
8. TPM PCR 7 enrollment if still part of bootstrap;
9. Secure Boot setup;
10. TPM PCR 0+2+7 re-enrollment;
11. automated health check;
12. manual checks that cannot be automated;
13. rollback/recovery links.

Commands must be copy-pasteable, with placeholders visibly marked.

### T8 Acceptance criteria

Search for duplicate TPM enrollment command blocks:

```bash
rg -n 'systemd-cryptenroll.*tpm2-pcrs' \
  docs/install-soyo.md hosts/soyo/DEPLOY.md docs/recovery.md
```

It is acceptable for recovery documentation to retain recovery commands. The deployment document should link rather than duplicate the canonical install sequence.

Run Markdownlint afterward.

### T8 Suggested commit

```text
docs(soyo): consolidate installation runbook
```

---

## T9 — Remove workstation-specific rekey path assumptions

Priority: Medium
Type: Operator portability
Risk: Medium because secrets workflows are sensitive

### T9 Problem

Host assemblers contain an absolute operator key path:

```nix
"/home/krzysiek/.ssh/soyo_ed25519"
```

The zbook assembler uses the same Soyo-named identity.

Relevant files:

- [Soyo assembler](../../modules/parts/soyo.nix)
- [zbook assembler](../../modules/parts/zbook.nix)
- [secrets guide](../secrets.md)

The string avoids copying the private key into the Nix store, which is correct. The gap is portability and naming, not secret exposure.

### T9 Safe improvement options

Choose one after checking agenix-rekey’s supported interface:

1. Use a neutral documented path such as:
   ```text
   ~/.ssh/agenix-master
   ```
   only if tilde expansion is actually supported—it often is not in Nix option strings.
2. Keep an absolute path but move it into a gitignored local module.
3. Read a path from a safe operator-side environment/config mechanism supported by evaluation.
4. Keep the current mechanism but rename the key and improve documentation.

Do not introduce `builtins.getEnv` casually. Impure evaluation would damage reproducibility and may break CI.

Do not turn a private key path into a Nix path literal, because that risks copying the key into the Nix store.

### T9 Acceptance criteria

- `nix flake check --no-build` works without the private key being present.
- `agenix rekey` remains documented and usable.
- No private key enters the store.
- Both hosts use the same clearly named master identity concept.
- `docs/secrets.md` matches the implementation.

### T9 Suggested commit

```text
refactor(secrets): clarify operator master identity path
```

---

## T10 — Investigate flake evaluation warnings

Priority: Low
Type: Maintenance
Risk: Medium if dependencies must change

### T10 Current warnings

`nix flake check --no-build` succeeds but prints:

```text
warning: unknown flake output 'agenix-rekey'
warning: unknown flake output 'deploy'
evaluation warning: 'system' has been renamed to/replaced by
'stdenv.hostPlatform.system'
```

### T10 Investigation steps

1. Determine which warning comes from local code and which comes from dependencies.
2. Run with a trace if necessary:
   ```bash
   nix flake check --no-build --show-trace
   ```
3. Inspect outputs:
   ```bash
   nix flake show
   ```
4. Check whether deploy-rs intentionally exposes `deploy` as a nonstandard output.
5. Check whether agenix-rekey intentionally exposes `agenix-rekey`.
6. Search local code for deprecated package-platform access:
   ```bash
   rg -n '\.system|inherit system|pkgs\.system|prev\.system' \
     flake.nix modules hosts lib
   ```

A likely local candidate is:

- [modules/parts/zbook.nix](../../modules/parts/zbook.nix), where an overlay uses `prev.system`.

Prefer:

```nix
prev.stdenv.hostPlatform.system
```

if that is the source and the attribute exists in the relevant overlay context.

### T10 Important constraint

Do not update `flake.lock` merely to remove harmless warnings unless explicitly authorized. Lock updates must use:

```bash
nix flake update <input>
```

### T10 Acceptance criteria

At minimum, eliminate locally controlled deprecation warnings.

Unknown custom-output warnings may remain if they are normal for the pinned integrations. If retained, document that they are expected rather than adding hacks around them.

### T10 Suggested commit

```text
fix(flake): replace deprecated platform system access
```

---

## Additional smaller improvements

These are suitable as follow-up tasks after the higher-priority work.

### A. Update stale flake description

Current:

```nix
description = "Multi-host NixOS flake; first host is the Soyo DNS/DHCP appliance";
```

Suggested direction:

```nix
description = "Multi-host NixOS flake for the Soyo LAN appliance and zbook workstation";
```

File:

- [flake.nix](../../flake.nix)

Acceptance:

```bash
nix flake check --no-build
```

### B. Stop manually counting modules in README

README says `modules/nixos/` contains a fixed number of files. Such counts drift quickly.

Either remove the count or generate it. Removing it is simpler and more robust.

### C. Strengthen health-check role detection

Current role detection infers “appliance” from a Tailscale route appearing in `tailscale status`.

File:

- [scripts/healthcheck.sh](../../scripts/healthcheck.sh)

Potential problems:

- advertised-route presentation may change;
- the local node may not display its own route as expected;
- a future appliance might not advertise the same subnet;
- a workstation could theoretically advertise a route.

Preferred direction:

- explicit role argument from a per-host wrapper; or
- a declarative marker installed by the host role, such as a read-only file under `/etc`.

Keep automatic detection as a fallback if useful.

### D. Avoid build-result symlink assumptions in CI

CI build jobs use `result` and then call `readlink -f result`.

Using:

```bash
nix build ... --no-link --print-out-paths
```

would make the closure path explicit and avoid workspace symlink state.

Ensure closure comparison still works before changing this.

### E. Add assertions for mutually incompatible host roles

Examples:

- a workstation should not accidentally enable DHCP;
- a non-server host should not enable remote unlock unless explicitly intended;
- Soyo should not enable NetworkManager;
- server networking should remain outside `base`;
- swap policy should remain outside `base`;
- GUI modules should remain outside `base`.

Some can be checked structurally by evaluating options; others may need source-oriented lint checks.

### F. Add topology freshness checking

Generated SVG files are committed, but CI builds topology only as an artifact. It does not appear to confirm that committed diagrams match generated output.

Possible check:

1. build topology;
2. compare generated SVGs with `docs/topology/`;
3. fail if they differ.

Be careful: SVG generation must be deterministic before enforcing this.

---

## Recommended milestone grouping

### Milestone A — Restore one coherent source of truth

Tasks:

- T1 architecture docs
- T2 desktop docs
- T8 install docs
- flake description/module-count cleanup

Outcome:

A new contributor or model can trust the written architecture.

### Milestone B — Protect the critical appliance roles

Tasks:

- T4 reservation validation
- T5 DNS/DHCP tests
- T6 resource-isolation enforcement
- T7 persistence checks

Outcome:

The major architectural invariants become executable checks rather than review conventions.

### Milestone C — Reduce maintenance drift

Tasks:

- T3 lint consolidation
- T9 rekey portability
- T10 warning cleanup
- topology freshness check

Outcome:

Local development, CI, documentation, and operations are less likely to diverge.

---

## Definition of done for the overall improvement pass

The improvement pass is complete when:

- `nix flake check --no-build` succeeds.
- Preferably, full `nix flake check` succeeds.
- Both host closures build.
- Canonical documentation describes `import-tree`, not a nonexistent registry.
- No active documentation references nonexistent `cosmic.nix`.
- All tracked shell and Python files receive their intended lint checks.
- Reservation duplicates and malformed data fail evaluation.
- DNS/DHCP generated configuration is tested.
- Soyo guest resource limits are tested.
- Persistence and backup expectations are tested.
- Soyo installation has one canonical runbook.
- Locally controlled deprecation warnings are gone.
- No boundary files or generated secrets were manually edited.
- Any deployment-impacting change is followed by:
  ```bash
  nix run .#healthcheck -- soyo
  nix run .#healthcheck -- zbook
  ```
- Boot, TPM, Secure Boot, and break-glass behavior remains manually verified where automation cannot prove it.
