# NixOS tests otherwise use `accel=kvm:tcg`, which can silently turn a useful
# integration test into a very slow emulation run.  Keeping this policy in one
# wrapper makes every repository-owned VM test fail fast when KVM is absent.
{ pkgs }:
test: pkgs.testers.runNixOSTest (test // { qemu.forceAccel = true; })
