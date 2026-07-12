# Testing and verification

The repository treats generated configuration, executable behavior, and
operator-only recovery as different evidence classes. The complete local gate
is `nix flake check path:. --keep-going`; focused checks are useful during
development, but do not replace it.

## KVM policy for VM checks

The DNS/DHCP, backup-unit, and impermanence checks require hardware
virtualization. Their shared test wrapper enables nixpkgs' `qemu.forceAccel`,
so QEMU fails immediately when `/dev/kvm` is missing or inaccessible instead
of silently falling back to slow TCG emulation. Each guest also verifies the
KVM clock source, providing runtime evidence that acceleration is active.

The complete local gate therefore requires readable and writable `/dev/kvm`.
Check access with `test -r /dev/kvm && test -w /dev/kvm` before starting it.
A hosted CI runner without KVM may explicitly skip only these three VM checks;
that skip must be visible in the job summary, while evaluation, static checks,
non-VM integration checks, and both host closure builds remain mandatory. A
runner with KVM must execute all three VM checks. TCG is not an accepted
substitute in either environment.

## CI and local KVM gates

GitHub's official runner documentation says nested virtualization on hosted
runners is experimental and carries no stability, performance or compatibility
guarantee. CI therefore does not pretend to provide a strict KVM resilience
gate. It evaluates every output, builds each non-VM check exactly once in its
named job, and builds both complete host closures.

| Trigger class | Evidence |
| --- | --- |
| Every push and pull request | Static hooks, documentation/public-data/workflow/shell policies, script contracts and topology freshness |
| Every push and pull request | Full no-build evaluation, pure invariants and isolated raw-restic integration |
| After static and evaluation pass | Complete Soyo and zbook closures; sanitized topology artifact |
| Required local KVM gate | DNS/DHCP packet exchange, impermanence reboot and backup-unit VM tests |

Run the hardware-accelerated resilience tier with:

```bash
test -r /dev/kvm -a -w /dev/kvm
just test-resilience
```

Then run `nix flake check path:. --keep-going` for the authoritative complete
repository gate. A future self-hosted or larger GitHub runner may add the same
named VM checks, but they must never be silently replaced by evaluation-only
success. See GitHub's
[hosted-runner warning](https://docs.github.com/actions/concepts/runners/github-hosted-runners#nested-virtualization).

The CI Cachix credential is available only on a push to `main`; pull requests,
including fork pull requests, cannot execute a step that references it. The
workflow token remains read-only. Closure comparison was removed because a
cached store-path string does not realize its closure in a fresh runner's Nix
store.

## Operational command contracts

The three operator-facing flake apps are tested with Bats. Bats was chosen over
another custom shell runner because named cases and per-test temporary
directories make cleanup and failure attribution explicit, while the tests
still execute the packaged commands as black boxes. Command doubles for SSH,
DNS, rage and Nix are themselves checked `writeShellApplication` packages;
tests never rewrite fixture executables in place.

| Contract | Expected exit status |
| --- | --- |
| Help, valid dry run, successful operation | 0 |
| Health check with one or more failed probes | 1 |
| Invalid host, role, interface, revision, secret source or confirmation | 2 |
| Interrupted secret mutation | 130; cleanup traps restore prior files |

`checks.script-contracts` covers argument boundaries, role selection, spaced
paths, exact subprocess argument vectors, timeout-like remote failures,
redaction, atomic rollback and dry-run non-mutation. Bats emits TAP in the
derivation log; CI does not currently consume JUnit, so no redundant report
artifact is generated.

## Shell boundaries

Shell code is checked at the boundary that actually executes it:

- NixOS `script`, `preStart`, `postStart`, `reload`, `preStop`, and `postStop`
  fragments use global `systemd.enableStrictShellChecks`. NixOS renders these
  through `writeShellApplication`, so warnings and undefined variables fail the
  system closure build.
- Repository-authored `ExecStart` helpers use `writeShellApplication` with
  explicit `runtimeInputs`. Tiny direct `ExecStart` commands use absolute Nix
  store paths; systemd does not invoke a shell for them.
- Standalone sources under `scripts/` and `tests/` are explicitly inventoried
  and passed directly to ShellCheck. A wrapper containing only `exec source.sh`
  would not count as checking the referenced source.

The `shell-boundaries` check rejects new standalone scripts until they are
classified, rejects repository `writeShellScript` calls, verifies that generated
unit fragments have strict checking enabled, and rejects non-absolute systemd
commands. Its mutation fixture demonstrates that an unchecked helper fails the
policy.

The three operator commands are first-class flake apps: `healthcheck`,
`recover-secrets`, and `set-tailscale-keys`. Their packages consume the actual
versioned source as `writeShellApplication.text`, rather than checking only a
one-line wrapper. `script-contracts` verifies help at an isolated command boundary,
pre-side-effect argument rejection, non-disclosing dry runs, and the absence of
automatic Git publication.

There are two upstream-owned exceptions:

- `dnsmasq`: the pinned module uses `mkdir -m 755 -p`, which triggers SC2174.
  The DHCP aspect separately declares lease-directory mode and ownership.
- `greetd`: the DMS greeter module's generated pre-start currently triggers
  SC2155, SC2162, and SC2035. The repository does not author that script.

The appliance DHCP and workstation Sway aspects own these scoped exceptions.
Repository-authored policy remains covered by evaluation and VM tests. Prefer
removing each exception once its pinned upstream module passes strict checking.

## Evidence limits

VM checks cover isolated software behavior, including DNS/DHCP, backup, and
impermanence. They do not prove physical TPM measurements, Secure Boot firmware
behavior, real LAN recovery, or restore operations against production data.
Those remain explicit operator-led drills in the relevant runbooks.
