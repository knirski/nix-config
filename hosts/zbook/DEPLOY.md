# zbook deployment

For a first install, follow [`hosts/zbook/INSTALL.md`](INSTALL.md).

For routine deployment of an existing installation:

- use [`docs/update-and-rollback.md`](../../docs/update-and-rollback.md) for
  routine deploys and rollback;
- use [`docs/recovery.md`](../../docs/recovery.md) for unlock failures, Secure
  Boot recovery, or hardware replacement;
- run `nix run .#healthcheck -- zbook` after deployment.

Do not copy installation sequences into this file. Keeping one canonical
runbook prevents disk, TPM, and secret-enrollment steps from drifting.
