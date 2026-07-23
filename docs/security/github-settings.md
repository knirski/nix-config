# GitHub security settings

The posture below was applied and read back through the GitHub API on
2026-07-12. The "Required status checks" section was independently re-read
on 2026-07-23 (task S2) and found to have drifted from that 2026-07-12
snapshot; see that section for specifics.

## Verified posture

- Repository visibility is public; the default branch is `main`.
- The default workflow token is read-only and cannot approve pull requests.
- Repository-level full-SHA Action enforcement is enabled.
- Secret scanning and push protection are enabled.
- Dependabot vulnerability alerts and security updates are enabled; updates are
  not automatically merged.
- Private vulnerability reporting is enabled and linked from `SECURITY.md`.
- The active `Protect main` ruleset requires pull requests, dismisses stale
  reviews, requires conversation resolution, blocks deletion and force pushes,
  and preserves a repository-administrator break-glass bypass.

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

### Currently enforced (re-verified read-only 2026-07-23)

`gh api repos/knirski/nix-config/rulesets/18830833` was re-read on 2026-07-23
while working task S2. Its `rules` array currently contains exactly:
`deletion`, `non_fast_forward`, `pull_request` (0 required approvals, stale
reviews dismissed, conversation resolution required, squash/merge only),
`creation`, and `required_linear_history` — **no `required_status_checks`
rule is present**. `gh api repos/knirski/nix-config/branches/main/protection`
separately confirms there is no classic branch-protection record either
(`404 Branch not protected`), so there is no other mechanism enforcing
status checks on `main`.

This means that, as of this reading, **no CI job's outcome currently gates
merging to `main`** — a pull request satisfying the rules above (contents
review dismissal/resolution, no force-push/deletion, linear history) can
merge regardless of whether `static`, `evaluation`, `build`, or `resilience`
passed. This contradicts the previous revision of this document (dated
2026-07-12), which asserted five contexts were required. Either that rule
was removed from the ruleset sometime after 2026-07-12, or the earlier
verification was inaccurate; a human with repository-admin access should
reconcile which is true and re-add the intended `required_status_checks`
rule. Until that happens, treat `main`'s CI as advisory-only, not a merge
gate, no matter what earlier prose in this repository implied.

### Recommended required-check set (not yet enacted)

The table below is this task's (S2) recommendation for the
`required_status_checks` rule's context list, to be added to ruleset
`18830833` only as a separate, explicitly authorized action (see
[Read-only verification](#read-only-verification) below for the inspection
commands to run immediately before that change, and re-run
`gh api repos/knirski/nix-config/rulesets/18830833` first to confirm the
ruleset's rule set hasn't moved again since this reading). Context names are
copied character-for-character from each job's `name:` field in
[`ci.yml`](../../.github/workflows/ci.yml), since that field — not the YAML
job key — is what GitHub displays and matches against.

| Context (from `ci.yml`'s job `name:`) | Status today | Recommendation |
| --- | --- | --- |
| `Static and repository policy` | Not enforced (see above) | Require — unchanged from the prior (stale) documented set |
| `Evaluation and pure invariants` | Not enforced | Require — unchanged |
| `Build soyo closure` | Not enforced | Require — unchanged |
| `Build zbook closure` | Not enforced | Require — unchanged |
| `Publish sanitized topology` | Not enforced | Require — unchanged |
| `Build ubuntu HM activation package` | Not enforced, not previously recommended | **New recommendation: require** |
| `Build macbook darwin closure` | Not enforced, not previously recommended | **New recommendation: require** |
| `Strict KVM behavior tests` | Not enforced, previously explicitly excluded | **New recommendation: require** |

Reasoning for the three additions:

- **`Build ubuntu HM activation package`** runs on the same `ubuntu-24.04`
  runner as every other required job (`static`, `evaluation`, `build`); it
  carries no additional platform risk. Ubuntu is a declared, first-class
  output with its own installation runbook
  ([`docs/install-ubuntu.md`](../install-ubuntu.md)), the same status
  soyo/zbook already have as required checks.
- **`Build macbook darwin closure`** runs on GitHub's `macos-latest` hosted
  runner via the same `./.github/actions/setup-nix` composite action
  (DeterminateSystems installer + magic-nix-cache + Cachix) used by every
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
macbook/ubuntu build failure — will only block a merge to `main` once a
repository administrator applies this recommendation to ruleset `18830833`
(or the currently-missing `required_status_checks` rule is otherwise
restored). It does not block merges today.

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
