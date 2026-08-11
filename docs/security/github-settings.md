# GitHub security settings

The posture below was read back through the GitHub API on 2026-08-01 after
the remediation changes described here.

## Verified posture

- Repository visibility is public; the default branch is `main`.
- The default workflow token is read-only and cannot approve pull requests.
- Repository-level full-SHA Action enforcement is enabled.
- Secret scanning and push protection are enabled.
- Dependabot vulnerability alerts and security updates are enabled; updates are
  not automatically merged.
- Private vulnerability reporting is enabled and linked from `SECURITY.md`.
- The active `Protect main` ruleset requires pull requests, dismisses stale
  reviews, requires conversation resolution and code-owner approval, blocks
  deletion and force pushes, and preserves a repository-administrator
  break-glass bypass.

The secret-bearing [PR Agent workflow](../../.github/workflows/pr-agent.yml) is
owned by [`.github/CODEOWNERS`](../../.github/CODEOWNERS). The ruleset's
`require_code_owner_review` setting is part of the security boundary; a
CODEOWNERS entry without that enforcement would only be advisory.

Base provider-pattern secret scanning runs automatically for public
repositories and is enabled here. Secret-scanning validity checks and generic
(formerly non-provider) patterns remain disabled because this is a user-owned
repository: GitHub documents both as GitHub Secret Protection features for
eligible organization-owned Team or Enterprise repositories. Repeated requests
through the 2022-11-28 and 2026-03-10 APIs were accepted but read back as
disabled; enabling public-repository Advanced Security separately returned that
it is already always available and did not change those entitlements.

The locked gitleaks check covers private keys and generic credential patterns
locally and in CI. GitHub push protection remains enabled for its supported
provider patterns.

## Required status checks

### Currently enforced (re-verified 2026-08-01)

`gh api repos/knirski/nix-config/rulesets/18830833` was updated and read back
on 2026-08-01. Its active `required_status_checks` rule requires these exact
contexts: `Static and repository policy`, `Evaluation and pure invariants`,
`Build soyo closure`, `Build zbook closure`, `Build ubuntu HM activation
package`, `Build macbook darwin closure`, `Strict KVM behavior tests`, and
`Publish sanitized topology`. The rule uses strict status checks and keeps the
existing repository-administrator bypass.

### Enforced required-check set

The enforced contexts are copied character-for-character from each job's
`name:` field in
[`ci.yml`](../../.github/workflows/ci.yml), since that field — not the YAML
job key — is what GitHub displays and matches against.

| Context (from `ci.yml`'s job `name:`) | Status today | Recommendation |
| --- | --- | --- |
| `Static and repository policy` | Enforced | Required |
| `Evaluation and pure invariants` | Enforced | Required |
| `Build soyo closure` | Enforced | Required |
| `Build zbook closure` | Enforced | Required |
| `Publish sanitized topology` | Enforced | Required |
| `Build ubuntu HM activation package` | Enforced | Required |
| `Build macbook darwin closure` | Enforced | Required |
| `Strict KVM behavior tests` | Enforced | Required |

Reasoning for the complete enforced set:

- **`Build ubuntu HM activation package`** runs on the same `ubuntu-24.04`
  runner as every other required job (`static`, `evaluation`, `build`); it
  carries no additional platform risk. Ubuntu is a declared, first-class
  output with its own installation runbook
  ([`docs/install-ubuntu.md`](../install-ubuntu.md)), the same status
  soyo/zbook already have as required checks.
- **`Build macbook darwin closure`** runs on GitHub's `macos-latest` hosted
  runner via the same `./.github/actions/setup-nix` composite action
  (DeterminateSystems installer + Cachix) used by every
  other job in this workflow — there is no macOS-specific fork of the setup
  step, so it carries the same installer reliability as the Linux jobs.
  Darwin closures do not need `/dev/kvm`, so this job does not inherit the
  hardware-virtualization caveat that excluded the KVM job below. Macbook is
  a declared output with its own runbook
  ([`docs/install-macbook.md`](../install-macbook.md)). No CI run in this
  repository's history shows this job flaking; its longer 120-minute timeout
  reflects darwin build time, not observed instability. (A separate task,
  H1, is reconciling the macbook *configuration's* agreement with its
  runbook prose — that is a content-correctness fix, not a CI-reliability
  concern, and does not block gating on "does the closure build".)
- **`Strict KVM behavior tests`** was excluded because `/dev/kvm` reliability
  on the hosted runner was in question and `clipboard-protocols` was
  nondeterministic. Both are now addressed: `ci.yml`'s `resilience` job
  fails closed with `test -c /dev/kvm && test -r /dev/kvm && test -w
  /dev/kvm` before running any check, and task C4 fixed
  `clipboard-protocols`' flakiness. `modules/parts/kvm-gate-drift-check.nix`
  additionally proves the four KVM checks this job builds
  (`backup-unit-vm`, `dns-dhcp-vm`, `impermanence-vm`,
  `clipboard-protocols`) can never silently drift from
  `lib/testing/kvm-checks.nix`'s canonical list or from `just
  test-resilience`.

A critical DNS/DHCP, impermanence, backup, or clipboard KVM failure — or a
macbook/ubuntu build failure — now blocks a merge to `main`, subject only to
the documented repository-administrator break-glass bypass.

Retain the administrator break-glass bypass (`bypass_actors` on the
ruleset) without weakening ordinary branch policy.

## Reporting vulnerabilities

Do not put credentials, exact recovery material, unpublished vulnerabilities,
or new sensitive topology in a public issue. Use the private reporting form
linked from the root `SECURITY.md`.

## Read-only verification

```bash
gh api repos/knirski/nix-config/actions/permissions
gh api repos/knirski/nix-config/actions/permissions/workflow
gh api repos/knirski/nix-config/rulesets
gh api repos/knirski/nix-config/rulesets/18830833
gh api repos/knirski/nix-config/rulesets/18830833 --jq '.rules[].type'
gh api repos/knirski/nix-config/branches/main/protection
gh api repos/knirski/nix-config --jq '.security_and_analysis'
gh api repos/knirski/nix-config/private-vulnerability-reporting
```
