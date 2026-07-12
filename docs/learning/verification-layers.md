# Learning verification layers

Nix can answer several different correctness questions, but no single command
answers all of them. This repository keeps the layers separate so a fast green
result is never confused with stronger runtime evidence.

## 1. Evaluation asks whether configuration composes

`nix flake check --no-build` evaluates flake outputs and NixOS modules. It
catches type errors, missing options, failed assertions and invalid module
composition. It does not prove that a service starts or that packets cross a
network boundary.

Project-owned transformations must not depend on realised derivations. CI
evaluates their checks and public outputs with
`allow-import-from-derivation false`. Grafana dashboard substitutions therefore
run in a normal build-time Python derivation, and the upstream nix-topology
operator output sits behind an explicit app rather than the recursively checked
package set.

The full host evaluation cannot disable IFD globally: agenix-rekey deliberately
realises the host-specific rekey derivation while resolving each secret's file.
In local storage mode it addresses each tracked `secrets/rekeyed/<host>` tree by
its named Nix store path. CI materialises only those encrypted source trees
before evaluation; it does not prebuild a host closure or decrypt a secret. The
ordinary no-build gate retains IFD for this documented upstream boundary, while
the narrower no-IFD gate prevents project code from silently adding more
evaluation-time builds.

## 2. Builds ask whether artifacts can be produced

Pure invariant checks and complete host closures turn evaluated plans into Nix
store paths. A successful Soyo closure proves that its service units, scripts,
kernel and activation artifacts build together. It still does not boot the
machine or exercise a network exchange.

Cachix reduces repeated work by substituting previously built paths. It does
not weaken verification: Nix checks the content-addressed result against the
expected store path. Pull requests use the cache without credentials; only
trusted pushes to `main` may upload new paths.

## 3. KVM tests ask whether isolated systems behave correctly

The repository has three NixOS VM tests:

- `dns-dhcp-vm` exchanges real DNS and DHCP packets;
- `backup-unit-vm` exercises the generated backup unit;
- `impermanence-vm` boots encrypted Btrfs state, reboots and verifies rollback.

Their shared wrapper forces QEMU acceleration and each guest checks its KVM
clock source. Missing or inaccessible `/dev/kvm` is therefore a failure, not a
slow TCG fallback. Locally and in CI, the complete gate is:

```bash
test -c /dev/kvm -a -r /dev/kvm -a -w /dev/kvm
nix flake check path:. --keep-going
```

The GitHub workflow performs the same preflight on `ubuntu-24.04`. The pinned
Nix installer enables KVM on that runner, and the job runs the whole flake suite
after static and evaluation tiers pass.

## 4. Mutation fixtures ask whether checks can detect bad changes

A check that only accepts the current tree might be accidentally ceremonial.
Mutation fixtures deliberately introduce malformed reservations, unsafe
workflow permissions, stale topology, missing persistence and other defects.
The check passes only when those variants are rejected for the intended reason.

This is why the workflow-policy test uses a YAML parser for structure rather
than regular expressions. YAML permits flow mappings, quoted values, lists and
comments; all must preserve the same security decision.

## 5. Physical drills ask what virtualization cannot prove

VMs cannot reproduce the real TPM, firmware Secure Boot measurements, NIC,
switch, direct-link rescue path or production backup target. Reboot/unlock,
restore and break-glass procedures remain operator-led drills with explicit
authorization. A green CI run is strong software evidence, not permission to
perform a destructive recovery exercise.

The practical rule is simple: use the cheapest layer during development, then
run every applicable stronger layer before merging or operating a host.
