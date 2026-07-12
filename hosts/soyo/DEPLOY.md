# Soyo installation and deployment

The canonical first-install runbook is
[`docs/install-soyo.md`](../../docs/install-soyo.md). Follow it from top to
bottom when provisioning or replacing Soyo; it covers destructive disk setup,
host-key creation, agenix rekeying, installation, TPM enrollment, Secure Boot,
validation, and recovery links.

For an existing installation:

- use [`docs/update-and-rollback.md`](../../docs/update-and-rollback.md) for
  routine deployments and rollback;
- use [`docs/recovery.md`](../../docs/recovery.md) for unlock failures, Secure
  Boot recovery, secret recovery, or hardware replacement;
- run `nix run .#healthcheck -- soyo` after deployment.

Do not copy an old installation command sequence into this file. Keeping one
canonical runbook prevents disk, TPM, and secret-enrollment steps from drifting.
