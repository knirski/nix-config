# Supply-chain policy

This flake has two dependency surfaces with different controls:

- Nix inputs are pinned by `flake.lock`. Update one input deliberately with
  `nix flake update <input>`, inspect the lock diff, and run the full flake gate
  plus both host builds.
- GitHub Actions are executable dependencies. Every `uses:` reference must be
  a full 40-character commit SHA with a nearby release comment. Mutable tags
  are documentation, never the trusted reference.

The `github-workflow-policy` flake check enforces immutable action references,
read-only top-level workflow permissions, and rejection of
`pull_request_target`. Actionlint remains responsible for workflow syntax and
expression correctness. Structural policy is parsed as YAML, while immutable
`uses:` references are checked line by line for actionable locations. Mutation
fixtures cover scalar, flow-mapping, comment, quoting and trigger variants.
These checks complement each other.

Cachix is a performance layer, not an authority boundary. Every job that
needs Cachix substitution passes a `cachix-auth-token` input to the local
`setup-nix` composite action; the value itself is what is gated, not merely
a later upload step. The input is computed as
`${{ (github.event_name == 'push' && github.ref == 'refs/heads/main') && secrets.CACHIX_AUTH_TOKEN || '' }}`,
which resolves to `secrets.CACHIX_AUTH_TOKEN` only when the run is a push to
`refs/heads/main`, and to the empty string for every other trigger —
`pull_request` (same-repo or fork), `workflow_dispatch`, and pushes to any
other branch. `setup-nix` then branches purely on whether that string is
empty: an empty token selects the pull-only `cachix-action` step (safe for
untrusted code, since no credential is present to leak or misuse), and a
non-empty token selects the push-enabled step. Because the gate lives on the
token *input* rather than on a downstream `run:` step, a same-repo pull
request build — which GitHub does expose repository secrets to — never
receives write access to the cache: the secret reference in the expression is
short-circuited away before the composite action ever sees it.

## Secret and public-data scans

The repository deliberately keeps two different policies:

- gitleaks detects credentials and high-confidence secret patterns;
- `public-repository-data` rejects operational topology details from artifacts
  explicitly promoted as public.

The normal local/CI working-tree command is:

```bash
nix run path:.#gitleaks -- detect --source . --no-git --redact --verbose
```

`--no-git` means exactly what it says: this scans the current source tree, not
Git history. A history audit is a separately named, deliberate operation:

```bash
nix run path:.#gitleaks -- git --redact --verbose
```

Both use the gitleaks package exposed from this repository's flake-locked
`nixpkgs` input. Redaction is mandatory in shared
logs; a scanner finding must not echo the value it is meant to protect. A
history finding still requires rotation or revocation first—removing a commit
does not invalidate a credential already copied elsewhere.

## Dependency automation decisions

This repository has two owned dependency-tree surfaces, not one:

- **Nix inputs**, pinned by `flake.lock` and updated via Renovate's `flake`
  manager (see `renovate.json`) or `nix flake update <input>`.
- **The vendored npm dependency tree for `command-code`**
  (`modules/_pkgs/command-code-lock/package-lock.json`), pinned by
  `modules/_pkgs/command-code.nix`'s `fetchurl` hash and `npmDepsHash`.
  `command-code` is an unfree, third-party npm package
  (`aspects.homeManager.development`, i.e. zbook/macbook/ubuntu — see task
  R1). Its upstream tarball ships no lockfile, so this repository generates
  and owns one, including a manually reviewed OpenTelemetry dependency-range
  override (`command-code-lock/opentelemetry-overrides.json`) that fixes
  CVE-2026-54285 (GHSA-8988-4f7v-96qf), which upstream's own `package.json`
  does not ship fixed. **This is a real, supported package-manager lock
  file with its own transitive dependency risk** — an earlier revision of
  this document incorrectly claimed the opposite ("this repository has no
  npm, Cargo, Go, Maven, Gradle or supported package-manager lock file") to
  justify deferring GitHub's dependency-review action. That claim was false
  and has been corrected.

That said, GitHub's dependency-review action still does not understand
`flake.lock` (the Nix-input surface), and reviewing `flake.lock` diffs
remains the manual process described above — nothing about correcting the
npm claim changes that. Dependency review also cannot substitute for the
npm-specific tooling below: it flags advisories on a PR diff, but has no way
to run the `postPatch` security-override transformation this repository
already applies, or to regenerate a lockfile the way `just update-command-code`
does. Given that, dependency review remains out of scope; the npm surface
instead gets its own purpose-built process:

- **Update process**: `just update-command-code <version>`
  (`scripts/update-command-code.sh`) fetches the named upstream tarball,
  prints the `fetchurl` hash, regenerates
  `command-code-lock/package-lock.json` in place (seeded from the
  currently-vendored lockfile so already-pinned resolutions are preserved),
  reapplies the OpenTelemetry override from
  `command-code-lock/opentelemetry-overrides.json`, and runs the documented
  fakeHash-then-build dance to print the resulting `npmDepsHash`. It never
  edits `command-code.nix`'s `version`/`hash`/`npmDepsHash` fields, never
  touches `flake.lock`, and never commits — a human pastes the printed
  values in after reviewing the regenerated lockfile's diff. Run against the
  current version, the script reproduces byte-identical hashes and lockfile
  content, proving it is deterministic.
- **Renovate**: deliberately does **not** get a `customManagers` entry for
  `command-code.nix`, even though Renovate's regex-based custom managers can
  target arbitrary files (including `.nix`) and there is prior art for
  pinning a `fetchurl` tarball this way. It was evaluated and rejected:
  Renovate has no way to compute the new `hash` (npm tarball sha512) or
  `npmDepsHash` a version bump requires — both need a real fetch/build,
  which a regex manager cannot perform without `postUpgradeTasks` (a
  self-hosted-only, explicitly-allowlisted Renovate feature not available
  here). A version-only regex bump would open a PR with a correct-looking
  version string and a now-stale hash, which fails `nix build` outright —
  worse than no automation, since it looks like progress but isn't. See
  `renovate.json`'s header comment for the same reasoning recorded next to
  the config itself.
- **Freshness check** (the alternative to Renovate automation):
  `tests/security/check_command_code_freshness.py` reads a locally-recorded
  `date` from `command-code-lock/last-reviewed.json` and fails if more than
  `staleAfterDays` (currently 180) have elapsed. It is deliberately **not**
  a `nix flake check` output: a `checks.*` derivation is cached by its
  time-independent inputs, so once built and substituted from Cachix it
  would never re-run just because time passed, silently freezing "pass"
  forever. `builtins.currentTime` would dodge that caching trap but requires
  `--impure`, which would break ordinary offline `nix flake check`. Instead
  it is a plain, offline, no-network script wired into `ci.yml`'s `static`
  job (runs on every push/PR, not just on a schedule) and into `just lint`
  for local use.
- **Vulnerability scan**: `pkgs.osv-scanner`, exposed as `apps.osv-scanner`
  from this flake's locked nixpkgs, scans
  `command-code-lock/package-lock.json` directly — the vendored npm tree,
  not merely `flake.lock`. Its default `scan source` mode queries deps.dev
  over the network for every resolved package, so it cannot be part of
  `nix flake check` (which must stay offline). It instead runs only in the
  new scheduled `.github/workflows/security-scan.yml`
  (`on: schedule` + `workflow_dispatch`), offset from Renovate's Monday
  flake-input schedule. A representative run during this task's
  implementation found a real, currently unaddressed high-severity finding
  — `@opentelemetry/propagator-jaeger@2.8.0` (GHSA-45rx-2jwx-cxfr, fixed in
  2.9.0) — distinct from the CVE-2026-54285 override already applied above,
  confirming the scan surfaces real advisories rather than passing
  vacuously. That specific finding is left for a human to triage (add a
  fifth entry to `opentelemetry-overrides.json` and re-run
  `just update-command-code`, or confirm it doesn't affect a code path this
  package actually exercises) rather than fixed silently as part of adding
  the scanning pipeline itself.
- **Offline build/smoke check**: `checks.command-code-security`
  (`modules/parts/command-code-security-checks.nix`) builds
  `packages.command-code`, smoke-tests the wrapped `cmd --version`, and
  proves the four OpenTelemetry packages in the built output's
  `node_modules` actually resolved to versions satisfying
  `opentelemetry-overrides.json`'s floors — not merely that `postPatch`
  claims to bump them. The same verification predicate
  (`tests/security/check_command_code_overrides.py`) is also run against
  checked-in negative fixtures under
  `tests/security/command-code-overrides/{pass,reject-*}/`, proving it
  actually rejects a vulnerable version and a dropped override, not just
  that it accepts the real build. This check is pure/offline and runs in
  ordinary `nix flake check`.

### Override ownership and lifecycle

This is a personal, single-operator repository: the repository owner is the
sole owner of the OpenTelemetry CVE-2026-54285 override (and any future
override added to `opentelemetry-overrides.json`). There is no separate
security team to hand this off to.

An override like this is expected to last until upstream `command-code`
ships a release whose own `package.json` already satisfies the bumped
range — i.e. until a `just update-command-code` run to a newer upstream
version no longer needs the `sed` bump because upstream's own pinned range
already clears the security floor. There is no fixed calendar expiry beyond
the 180-day freshness window above, which forces a periodic look regardless
of whether upstream has caught up.

To remove an override once it's no longer needed:

1. Delete the corresponding entry from
   `command-code-lock/opentelemetry-overrides.json` (this is the single
   place both `command-code.nix`'s `postPatch` and
   `scripts/update-command-code.sh` read from, so no other file needs a
   matching edit).
2. Run `just update-command-code <version>` to regenerate the lockfile
   without that override applied, and rebuild:
   `nix build path:.#command-code`.
3. Confirm `nix build path:.#checks.x86_64-linux.command-code-security`
   still verifies successfully with the override removed — it will, since
   upstream's own now-current range already satisfies the same floor
   recorded in the (now-shorter) overrides list.
4. Update `command-code-lock/last-reviewed.json`'s `date` and commit
   the override-list, lockfile, and freshness-record changes together.

OpenSSF Scorecard is also deferred until the repository settings in
[GitHub security settings](github-settings.md) are enabled and the operator has
explicitly decided whether public Scorecard/SARIF results are desirable. It
must not receive `security-events: write` merely to improve a badge.

Automatic dependency merging is out of scope. Reproducibility is preserved by
reviewing lock changes and validating built systems, not by accepting updates
unattended.

## Nixpkgs unfree and insecure package policy

`lib/mk-nixpkgs-args.nix` centralizes `nixpkgs.config` (`allowUnfree`,
`permittedInsecurePackages`) and the `command-code`/`gcx` package overlay so
they can't drift between the NixOS, darwin, and standalone Home Manager host
assemblers.

- **`allowUnfree = true`** stays global, unconditional, and identical on
  every host, including Soyo. This is a licensing acknowledgment, not a
  security boundary — the repository owner has deliberately decided
  per-host scoping here would add complexity with no real security benefit.
- **The `command-code`/`gcx` overlay** also stays global. It looks like it
  should be scoped alongside `command-code`'s Home Manager installation
  (confined to `aspects.homeManager.development` — zbook/macbook/ubuntu,
  not Soyo), but `gcx` is installed unconditionally by
  `aspects.homeManager.base` on every Linux host (`modules/home/base.nix`),
  Soyo included — confirmed via `nix eval` against
  `nixosConfigurations.soyo`'s evaluated `home.packages`. Scoping the
  overlay away from Soyo would break Soyo's real package resolution, so
  leaving it global is required, not merely harmless.
- **`permittedInsecurePackages`** is scoped per host. Unlike the two
  policies above, an insecure-package allowance is genuinely
  host-specific: only bitwarden-desktop (pulled in by
  `aspects.homeManager.desktop`, which zbook/macbook/ubuntu enable but Soyo
  does not) depends on the EOL `electron_39` (`electron-39.8.10`). Soyo, a
  headless appliance, has no use for it.

### The reviewed exception registry

`lib/insecure-package-exceptions.nix` is the single source of truth: a list
of attrsets, each requiring `package`, `knownVulnerability`, `rationale`,
`owner`, `reviewed` (ISO-8601 date), and `reviewIntervalDays`. Consumers:

- `modules/parts/zbook.nix`, `modules/parts/macbook.nix`, and
  `modules/parts/ubuntu.nix` each map the registry's `package` field into
  their own `nixpkgs.config.permittedInsecurePackages` — Soyo (the other
  consumer of `aspects.nixos.base`) never imports this file, so it carries
  none of it. `nixpkgs.config` in the NixOS/darwin module system merges
  disjoint keys across separate module definitions without conflict, which
  is what lets the shared `nixos.base`/`darwin.base` aspects (which set
  `allowUnfree` for every host) and a host's own added
  `permittedInsecurePackages` definition coexist without one clobbering the
  other, regardless of definition order — verified with `nix eval` against
  the real host outputs, not assumed from reading the module source.
- `checks.nixpkgs-policy-invariants`
  (`modules/parts/nixpkgs-policy-checks.nix`) is the enforcement layer: it
  proves (a) Soyo's evaluated `nixpkgs.config.permittedInsecurePackages` is
  empty, (b) every registry entry has well-formed, non-empty rationale/
  owner/review metadata (checked against hand-mutated negative fixtures
  under `tests/nixpkgs-policy/insecure-exception-mutations.nix`, so the
  check is proven to actually reject a malformed entry, not merely accept
  the one real entry that happens to be well-formed), and (c) zbook/
  macbook/ubuntu's evaluated `permittedInsecurePackages` exactly match the
  registry, so the registry can't silently drift from what's actually
  wired into the hosts.

Adding a future exception means adding an entry to
`lib/insecure-package-exceptions.nix` with all required fields (the check
rejects anything less) and wiring the affected host(s) to consume it the
same way zbook/macbook/ubuntu do. Removing one that's no longer needed means
deleting its entry and the corresponding host wiring — the check will fail
loudly if a host's evaluated `permittedInsecurePackages` and the registry
ever disagree.
