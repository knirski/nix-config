# GitHub security settings

The posture below was applied and read back through the GitHub API on
2026-07-12.

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

## Required-check transition

Required status checks are temporarily deferred because the completed local CI
workflow renames every context currently reported by GitHub. Requiring either
name set during the transition would block the other.

After the rewritten workflow reaches `main`, add these contexts to ruleset
`18830833`, using names confirmed by its first successful run:

- `Static and repository policy`
- `Evaluation and pure invariants`
- `Build soyo closure`
- `Build zbook closure`
- `Publish sanitized topology`

Do not guess the final contexts before that run. Ruleset mistakes can block
recovery work; retain the administrator break-glass path without weakening
ordinary branch policy.

## Reporting vulnerabilities

Do not put credentials, exact recovery material, unpublished vulnerabilities,
or new sensitive topology in a public issue. Use the private reporting form
linked from the root `SECURITY.md`.

## Read-only verification

```bash
gh api repos/knirski/nix-config/actions/permissions
gh api repos/knirski/nix-config/actions/permissions/workflow
gh api repos/knirski/nix-config/rulesets
gh api repos/knirski/nix-config --jq '.security_and_analysis'
gh api repos/knirski/nix-config/private-vulnerability-reporting
```
