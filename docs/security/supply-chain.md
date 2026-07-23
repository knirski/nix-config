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

GitHub dependency review does not currently understand `flake.lock`, and this
repository has no npm, Cargo, Go, Maven, Gradle or supported package-manager
lock file. Adding the action would produce a reassuring green check without
reviewing the primary dependency surface, so it is deferred.

OpenSSF Scorecard is also deferred until the repository settings in
[GitHub security settings](github-settings.md) are enabled and the operator has
explicitly decided whether public Scorecard/SARIF results are desirable. It
must not receive `security-events: write` merely to improve a badge.

Automatic dependency merging is out of scope. Reproducibility is preserved by
reviewing lock changes and validating built systems, not by accepting updates
unattended.
