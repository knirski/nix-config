# Public repository data policy

This repository is public by design: it teaches an idiomatic NixOS setup and
makes the configuration reproducible. Public does not mean that every generated
operator view should be published. This policy separates useful architecture
from detailed operational inventory.

## Data classes

| Class | Examples | Repository policy |
| --- | --- | --- |
| Credentials and authentication material | Private keys, passwords, recovery codes, tokens, unencrypted secret values | Never commit. Store service and password material through agenix-rekey; scan with gitleaks. |
| Personal data | Personal email addresses, non-public account identifiers, names not needed to teach the design | Omit unless there is a reviewed operational need. |
| Operational metadata | Exact addresses, MACs, disk IDs, interfaces, usernames, device names, rescue networks, backup destinations and trust relationships | May exist in declarative host data and operator runbooks, but must not appear in the public overview diagram. Avoid unnecessary repetition. |
| Public architecture | Host roles, critical-versus-guest boundaries, abstract LAN/VPN/Internet flows, encrypted backup and upstream DNS relationships | Suitable for the README and public overview after automated review. |

RFC 1918 addresses and MAC addresses are identifiers, **not credentials or
secrets**. They remain legitimate plaintext inputs to the declarative network
configuration. However, combining them with hostnames, physical interfaces,
backup targets and recovery paths creates a useful reconnaissance map. The
diagram policy therefore treats that aggregate as sensitive operational
metadata even though its individual values are not secret.

Gitleaks remains the credential scanner. The separate `public-repository-data`
flake check enforces this narrower publication policy; neither check is a
substitute for the other.

## Diagram profiles

Two deliberately different profiles are supported:

- `publicOverview` is a small, generated architecture view intended for the
  README. Its visible text comes from a reviewed vocabulary of generic roles
  and flows. It must contain no exact IP or MAC address, disk identifier,
  username, interface name, personal LAN device label or rescue addressing.
  It also rejects active SVG content and external resources.
- `operatorDetailed` is the locally generated troubleshooting view. It may
  contain exact host and network inventory. It is not a README artifact and
  must not be uploaded or committed in future revisions.

The former `docs/topology/main.svg` and `docs/topology/network.svg` predated this
policy and were detailed operator outputs. They are no longer tracked or
published. The README embeds only the generated `docs/topology/overview.svg`;
`just topology-operator-detailed` retains local troubleshooting output without
creating a publication path.

## Existing exposure and residual risk

The detailed diagrams, host configuration and historical documentation are
already present in public Git commits. GitHub issue
[#2](https://github.com/knirski/nix-config/issues/2) also records an exact disk
identifier, LAN and rescue-adjacent setup details, an interface name and an
early bootstrap procedure. Closing or editing the issue would not erase its
history or copies held by forks and caches.

This policy stops increasing the prominence and future publication of detailed
diagrams; it does not claim to retract data already published. Rewriting Git
history is disruptive, does not guarantee removal from forks or caches, and is
outside this work. If a credential is ever exposed, rotate or revoke it first
and follow GitHub's
[sensitive-data removal guidance](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).

## Adding a public artifact

1. Prefer generic roles and data flows over inventories.
2. Add the artifact explicitly to the `public-repository-data` check. Files are
   not assumed safe merely because they live under `docs/`.
3. Extend the visible-text allowlist only for a reviewed architectural term.
4. Add a failing fixture for every new prohibited token or SVG feature.
5. Run `nix build path:.#checks.x86_64-linux.public-repository-data --no-link`
   and the normal gitleaks scan before publishing.

The check is intentionally scoped to designated public-facing artifacts. It
does not scan educational examples, host data or operator runbooks for private
address literals, because doing so would create false confidence and prevent
those documents from being precise.
