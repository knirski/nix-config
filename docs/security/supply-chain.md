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
expression correctness. These checks complement each other.

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
