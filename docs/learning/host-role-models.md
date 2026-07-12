# Learning host role models

A host role answers two questions: what responsibilities may this machine
carry, and what must never leak into another machine? NixOS offers several ways
to encode that decision. They differ mainly in how visible composition remains.

## The current model: explicit aspects

Each reusable feature exposes an aspect such as `aspects.nixos.server` or
`aspects.nixos.workstation`. A host assembler explicitly selects aspects:

```nix
with config.aspects.nixos; [ base server users persistence blocky dhcp ]
```

This is intentionally repetitive. A reviewer can open one assembler and see
the host's complete capability set. Separate invariant checks evaluate the
composed configurations and reject server services on zbook, workstation
services on Soyo, or unbounded guest units.

## Alternative 1: reusable profile modules

A conventional NixOS repository may create `profiles/server.nix` and import it
from each host. This is simple and works without flake-parts. The trade-off is
that nested imports hide the final feature list: understanding a host requires
following the profile's imports recursively. Profiles are a good fit when many
hosts share nearly identical bundles.

## Alternative 2: one typed role option

A module can define an enum such as:

```nix
options.myFleet.role = lib.mkOption {
  type = lib.types.enum [ "lan-appliance" "workstation" ];
};
```

Other modules use `mkIf` against that value. This gives excellent validation
and a single discoverable label, but it assumes roles are mutually exclusive.
Real hosts often combine orthogonal concerns—server, laptop, graphical desktop,
backup client—so one enum can grow into an awkward matrix.

## Alternative 3: a typed fleet registry

A fleet-level registry records metadata separately from NixOS implementation:

```nix
hostMeta.soyo.roles = [ "lan-appliance" "backup-client" ];
hostMeta.zbook.roles = [ "workstation" "laptop" "backup-client" ];
```

Checks can derive expected capabilities and forbidden combinations from this
registry. Documentation and topology can also consume its public subset. This
scales well, but automatically generating all imports from roles can obscure
which code a host enables.

The best incremental option here would keep assemblers explicit and add the
registry only as independently checked metadata. Assertions would compare the
declared roles with evaluated capabilities. A mismatch would fail evaluation;
the registry would not silently enable services.

## Alternative 4: module classes and capability contracts

Larger fleets can model each role as a contract: required options, provided
capabilities and conflicts. A server role might provide `remote-administration`
while the LAN-appliance role requires `static-networking` and conflicts with
`network-manager`. This is expressive, but introduces a custom framework that
new contributors must learn. It is worthwhile only when many hosts and role
combinations make direct assertions repetitive.

## Alternative 5: NixOS specialisations

Specialisations produce multiple bootable configurations for one physical
host. They are useful for variants such as normal versus debugging kernels or
GPU modes. They are not a fleet role system: using them for server versus
workstation ownership would mix runtime boot choices with architectural
boundaries.

## Recommendation for this repository

Keep explicit dendritic aspects and evaluated boundary checks. If a third or
fourth host makes role metadata repetitive, add a typed registry whose claims
are compared with the assembled configuration. Do not generate critical DNS or
DHCP ownership solely from a label: the assembler should remain the visible
point where those responsibilities are accepted.
