# Backup Restore VM Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing backup KVM test to prove that a successful configured restic snapshot can restore its payload after source loss.

**Architecture:** Keep the behavior in the existing `backup-unit-vm` NixOS test. The test will use the real configured systemd backup unit to create a local repository snapshot, remove the source, restore the latest snapshot into a separate target, verify content and mode, then copy the restored source back so the existing password-failure and later-success cases remain independent.

**Tech Stack:** NixOS VM tests, Python testScript, restic, systemd, Nix flakes, Markdown documentation.

## Global Constraints

- Use the existing `backup-unit-vm` check; do not create another VM derivation.
- Keep the repository and password local to the fixture; never contact the production NAS.
- Preserve the existing wrong-password, `OnFailure`, and later-success assertions.
- Require readable and writable `/dev/kvm`; never fall back to TCG emulation.
- Keep production restore, SFTP transport, and real credentials as manual-only evidence.
- Do not modify `flake.lock`, `secrets/rekeyed/`, or generated host facter files.

---

### Task 1: Add deterministic local restore coverage

**Files:**
- Modify: `modules/parts/backup-integration-check.nix` in the `backup-unit-vm` `testScript`
- Modify: `docs/testing.md` in the backup test matrix and evidence limits
- Modify: `docs/learning/project-assessment.md` in the backup coverage summary

**Interfaces:**
- Consumes: the existing `restic-backups-fixture.service`, local repository at `/var/lib/restic-fixture/repository`, password file at `/run/restic-fixture/password`, and source at `/var/lib/restic-fixture/source`.
- Produces: a passing `backup-unit-vm` check that proves restoration into `/var/lib/restic-fixture/restore/var/lib/restic-fixture/source`.

- [ ] **Step 1: Add the failing restore assertion first**

Immediately after the existing successful-backup assertions, add a subtest that models source loss and checks the restored path before adding the restore command:

```python
with subtest("a successful snapshot restores after source loss"):
    machine.succeed("rm -rf /var/lib/restic-fixture/source")
    machine.succeed("install -d -m 0755 /var/lib/restic-fixture/restore")
    machine.succeed("test ! -e /var/lib/restic-fixture/source/nested/file")
    machine.succeed("test -e /var/lib/restic-fixture/restore/var/lib/restic-fixture/source/nested/file")
```

- [ ] **Step 2: Run the focused check to verify the new assertion fails for the intended reason**

Run with elevated KVM access:

```bash
test -c /dev/kvm && test -r /dev/kvm && test -w /dev/kvm
nix build --no-link path:.#checks.x86_64-linux.backup-unit-vm
```

Expected: the VM test fails at the new restored-path assertion because no restore operation has been added yet.

- [ ] **Step 3: Implement the minimal restore flow and preserve later cases**

Replace the temporary assertion-only block with this complete sequence after the successful backup assertions:

```python
with subtest("a successful snapshot restores after source loss"):
    machine.succeed("rm -rf /var/lib/restic-fixture/source")
    machine.succeed("rm -rf /var/lib/restic-fixture/restore")
    machine.succeed("install -d -m 0755 /var/lib/restic-fixture/restore")
    machine.succeed("test ! -e /var/lib/restic-fixture/source/nested/file")
    machine.succeed(
        "RESTIC_REPOSITORY=/var/lib/restic-fixture/repository "
        "RESTIC_PASSWORD_FILE=/run/restic-fixture/password "
        "restic restore latest "
        "--target /var/lib/restic-fixture/restore "
        "--include /var/lib/restic-fixture/source"
    )
    restored = "/var/lib/restic-fixture/restore/var/lib/restic-fixture/source/nested/file"
    machine.succeed(f"test \\\"$(cat {restored})\\\" = 'payload'")
    machine.succeed(f"test \\\"$(stat -c %a {restored})\\\" = 640")
    machine.succeed(
        "cp -a /var/lib/restic-fixture/restore/var/lib/restic-fixture/source "
        "/var/lib/restic-fixture/source"
    )
```

Before the existing successful-backup case, set the fixture mode that the
restore assertion will verify:

```python
machine.succeed("chmod 0640 /var/lib/restic-fixture/source/nested/file")
```

The source file must be created with the known payload and this mode before
the backup runs, and the restore target must be removed before the restore so
stale files cannot satisfy the assertions. Keep the
existing wrong-password case after this block; the copy-back restores its
precondition without changing the repository or password semantics.

- [ ] **Step 4: Update documentation to distinguish automated and manual restore evidence**

Change the `backup-restic-integration` row in `docs/testing.md` from “initialise a repo, backup, and check a snapshot” to “initialise a repo, backup, restore, and check a snapshot”. In the evidence-limits section, state that the VM proves local snapshot restoration while SFTP/NAS transport and a production restore remain manual.

Update the backup coverage entry in `docs/learning/project-assessment.md` to mention both the existing `restic check --read-data` and the new local restore assertion, without claiming production restore coverage.

- [ ] **Step 5: Run the focused check and verify it passes**

Run:

```bash
nix build --no-link path:.#checks.x86_64-linux.backup-unit-vm
```

Expected: exit 0, including successful backup, restore-after-deletion, wrong-password failure handoff, and later-success subtests.

- [ ] **Step 6: Run repository verification**

Run:

```bash
nix flake check path:. --no-build --show-trace
nix build path:.#checks.x86_64-linux.pre-commit path:.#checks.x86_64-linux.docs-correctness --no-link
git diff --check
```

Expected: all commands pass; only the repository’s documented tool-owned flake output warnings may appear.

- [ ] **Step 7: Commit the implementation**

```bash
git add modules/parts/backup-integration-check.nix docs/testing.md docs/learning/project-assessment.md
git commit -m "test: verify backup snapshot restoration"
```
