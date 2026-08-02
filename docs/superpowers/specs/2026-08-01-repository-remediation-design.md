# Repository Remediation Design

Date: 2026-08-01

## Goal

Close the actionable security, CI, portability, source-hygiene, testing, and
documentation gaps found in the current repository assessment without
deploying, rebooting, rekeying, or changing host hardware.

## Scope and decisions

### Supply chain and CI trust

- Refresh the vendored `command-code` dependency tree only through the normal
  upstream update workflow. Do not carry a repository-local OpenTelemetry
  advisory override; the next command-code release is expected to resolve
  that advisory. Keep the OSV scan visible so an upstream release can be
  verified when it arrives.
- Restrict the PR Agent workflow to the permissions it actually needs and keep
  the external AI secret away from untrusted pull-request execution. The
  review workflow remains advisory and comment-only.
- Add the complete supported CI matrix to the `Protect main` GitHub ruleset's
  required status checks. This is an explicitly authorized repository-admin
  API change, not a Nix source change.

### Hermetic local gates

- Make Nix-backed source checks independent of known local checkout artifacts.
  Preserve tracked `.commandcode` taste files while excluding local agent
  settings and worktrees; pure Nix does not have a reliable Git-index API, so
  this is intentionally a bounded artifact filter rather than a tracked-file
  manifest.
- Ignore `.commandcode/settings.json` and `.claude/` locally. Existing user
  files remain untouched.
- Add regression coverage proving nested worktree paths cannot bypass the
  generated-source exclusions.

### Portability and host contracts

- Remove the shared SSH aspect's hardcoded `zbook_ed25519` identity. Use the
  default agent/key discovery for GitHub and retain host aliases without
  enabling agent forwarding by default.
- Add a platform-aware healthcheck contract: NixOS hosts retain the current
  systemd/persistence probes; macOS and standalone Ubuntu receive explicit
  platform checks or a clear unsupported result rather than false NixOS
  failures.
- Extend namespace-contract checks to Darwin and standalone Home Manager
  configurations.
- Keep macbook's system-level agenix/Tailscale/backup limitations explicit;
  do not invent unsupported launchd equivalents before hardware validation.

### Operations and documentation

- Add static contracts for the missing observability alert families and
  document the remaining live restore, TPM, and hardware-only gates.
- Reconcile `docs/status.json`, `docs/README.md`, and the remediation plan's
  lifecycle status.
- Keep the `nix flake check` warnings for the tool-owned `deploy` and
  `agenix-rekey` namespaces explicitly documented. They are consumed by
  deploy-rs and agenix-rekey, not repository-owned standard outputs, so
  manufacturing duplicate `packages` or `apps` aliases would add noise rather
  than improve the interface.

## Verification

The implementation must pass, where supported by the current environment:

1. targeted regression tests before each implementation change;
2. `nix flake check path:. --no-build --show-trace`;
3. Linux host and Ubuntu activation builds;
4. non-KVM contract and integration checks;
5. the full static derivation, gitleaks, and command-code freshness check;
6. the four KVM checks, freshly when the local KVM runner is available;
7. a read-only GitHub API readback confirming required status checks.

Live deployment, reboot, secret rekeying, restore, and hardware validation
remain outside this change.
