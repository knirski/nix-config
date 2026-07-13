# GitHub issue #2 reconciliation

> **Status: Completed reconciliation record.** Issue
> [#2, Bootstrap Soyo from NixOS Live USB](https://github.com/knirski/nix-config/issues/2)
> was closed as completed on 2026-07-12 after a comment linked the canonical
> installation, secrets and recovery runbooks.

The issue captured the first bootstrap checklist. The canonical replacement is
[Install Soyo](../install-soyo.md), supported by the [secrets](../secrets.md) and
[recovery](../recovery.md) runbooks. The comparison below preserves the safety
intent without repeating exact host inventory.

| Issue section or safety gate | Current replacement | Result |
| --- | --- | --- |
| Live environment and required tools | Install guide: prerequisites and live-ISO preparation | Preserved |
| Verify the target disk before wiping | Install guide: identify target disk and destructive safety gate | Preserved |
| Evaluate and build before touching disk | Install guide: preflight validation | Preserved |
| Partition, encrypt and mount with disko | Install guide: disko installation | Preserved |
| Create the immutable blank root snapshot | Install guide: blank-snapshot verification | Preserved |
| Create initrd and stage-two SSH host keys | Install guide: separate early-boot and durable keys | Preserved |
| Register the host recipient and rekey secrets | Install guide: agenix host key and rekey flow | Added after the issue |
| Enroll TPM PCR 7 while retaining passphrase | Install guide: phase-one enrollment | Preserved |
| Install and perform first boot | Install guide: installation and first boot | Preserved |
| Validate DNS, PTR, services and secrets | Install guide: automated health check and manual checks | Expanded |
| Cut DHCP over without competing servers | Install guide: controlled DHCP cutover | Added after the issue |
| Enable Secure Boot and re-enroll PCR 0+2+7 | Install guide: phase-two hardening | Added after the issue |
| Recover through console, initrd SSH or direct link | Recovery runbook | Expanded |

The issue's temporary sudo limitation is obsolete: password secrets and the
current immutable-user flow are declarative. Its branch-specific clone command
is also obsolete; installations use the reviewed default branch/revision.

No unique safety instruction remains only in the closed issue.
