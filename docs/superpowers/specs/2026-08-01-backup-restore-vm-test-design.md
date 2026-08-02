# Backup Restore VM Test

## Context

The existing `backup-unit-vm` check exercises the real configured restic
systemd unit, including successful backup metrics, wrong-password failure
metrics, and the local `OnFailure` handoff. It does not yet prove that a
successful snapshot can restore the backed-up data.

## Goal

Add deterministic automated coverage for local snapshot restoration without
contacting the production NAS or depending on external credentials.

## Design

Extend the existing `backup-unit-vm` test in
`modules/parts/backup-integration-check.nix`:

1. Create a nested fixture source containing a known payload and metadata.
2. Run the configured backup unit successfully.
3. Remove the source tree to model data loss.
4. Restore the latest snapshot into a clean restore directory using the same
   restic repository and password file.
5. Verify the restored nested path, payload, and file mode.

The restore assertion belongs immediately after the successful backup case so
it uses the known-good repository state before the wrong-password case mutates
the password file. The existing failure and later-success cases remain
unchanged.

## Scope boundaries

The test proves the repository produced by the configured local backup unit is
restorable. It does not prove SFTP transport, production NAS availability,
production credentials, or a full operator-led restore procedure; those remain
manual recovery drills.

Documentation will update the testing matrix and evidence limits to describe
the new local restore coverage and retain those manual limitations.

## Verification

Run the focused `backup-unit-vm` KVM check, then the full flake check and
documentation/pre-commit checks. The KVM check requires readable and writable
`/dev/kvm` and must not fall back to software emulation.
