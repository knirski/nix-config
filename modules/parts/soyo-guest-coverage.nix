# flake-parts module: deny-by-default classification check for Soyo's systemd
# services. The sibling soyo-guest-isolation.nix validates that every name in
# the guest list HAS MemoryMax/CPUQuota/Nice-or-IOWeight; this check validates
# the inverse contract: every systemd service unit on Soyo is EITHER on the
# guest list (lib/soyo-guest-units.nix) OR explicitly excluded by a named
# nonGuestUnits entry (with a reason) or a tight nonGuestPatterns match
# (systemd-*, getty).
#
# Why: AGENTS.md invariant 2 ("every guest service gets MemoryMax, CPUQuota,
# lowered Nice/IOWeight") is only enforceable against a known guest set. With
# only an allowlist, a future aspect that lands a new guest service without
# registering it runs unisolated and nothing notices — exactly the seam M4
# expansion (Jellyfin, Vaultwarden, …) will stress. This check makes that
# omission a hard CI failure with a targeted, copy-pasteable remediation hint.
#
# Blocky and dnsmasq (invariant 1: DNS and DHCP are the only critical roles)
# and OpenSSH/boot/network units (operator/recovery infrastructure) live below
# in nonGuestUnits with reasons, never on the guest list.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      soyo = inputs.self.nixosConfigurations.soyo.config;
      actualUnits = builtins.attrNames soyo.systemd.services;
      guestUnits = (import ../../lib/soyo-guest-units.nix) soyo;

      # Explicitly-classified non-guest units on soyo today. Each entry needs an
      # inline reason; entries with no rationale are caught at code review and
      # by the failure message when a future change probes them. Critical
      # roles (blocky, dnsmasq) are invariant-1 sacred and never isolated.
      nonGuestUnits = [
        # Critical roles (AGENTS.md invariant 1).
        "blocky"
        "dnsmasq"

        # Operator recovery: sshd units are never resource-isolated — root
        # shell access during an outage must not be capped by a cgroup.
        "sshd"
        "sshd-keygen"
        "sshd@"
        "sshd-vsock@"

        # Network / firewall / boot-time infrastructure.
        "nftables"
        "network-local-commands"

        # Boot / shutdown / power / kernel helpers.
        "generate-shutdown-ramfs"
        "prepare-kexec"
        "sleep-actions"
        "post-boot"
        "tpm2-udev-trigger"
        "kmod-static-nodes"
        "modprobe@"
        "reload-systemd-vconsole-setup"
        "suid-sgid-wrappers"

        # Per-user and login subsystem.
        "user@"
        "user-runtime-dir@"
        "linger-users"
        "lastlog2-import"

        # System-wide daemons and config helpers.
        "dbus"
        "dbus-broker"
        "nscd"
        "earlyoom"
        # Headless soyo: bluetoothd is plumbed by an upstream NixOS module
        # setting hardware.bluetooth on a box with no radio; the unit is
        # harmless and not a guest workload.
        "bluetooth"
        "logrotate"
        "logrotate-checkconf"
        "smartd"
        "nix-daemon"
        "home-manager-krzysiek"

        # maintenance.nix schedules nix.gc weekly; nix-gc deliberately runs
        # unisolated by deferral. Its sibling nix-store-optimise IS isolated
        # (see the guest list); a tight MemoryMax on gc risks OOM-killing a
        # concurrent nix-collect-garbage store scan, and a considered cap is
        # deferred until M4 pressure forces the decision. Removing this entry
        # requires ONE of: add MemoryMax/CPUQuota/Nice to nix-gc in
        # modules/nixos/maintenance.nix AND move "nix-gc" to the guest list in
        # lib/soyo-guest-units.nix; or re-record the decision here with a
        # fresh reason.
        "nix-gc"

        # modules/nixos/base.nix sets `services.nix-optimise.enable = false`
        # (the comment there explains the separate weekly nix-store-optimise
        # guest that supersedes the upstream unit). Its presence in
        # systemd.services is the disabled unit still occupying the namespace.
        "nix-optimise"
      ];

      # Pattern-based exclusions for upstream-defined unit families that by
      # convention will never host a guest workload. Each pattern widens what
      # counts as "infrastructure" — a deliberate invariant lever; tighten
      # only with a code-review reason.
      nonGuestPatterns = [
        # All of systemd's own units: journald, logind, networkd, udevd,
        # machine-id-commit, … Guests use their service names; none names itself
        # with a "systemd-" prefix.
        (name: lib.hasPrefix "systemd-" name)
        # Every getty / login-window unit (console-getty, getty@,
        # serial-getty@, container-getty@). No guest names itself with "getty".
        (name: lib.hasInfix "getty" name)
      ];

      matchesAnyPattern = name: lib.any (p: p name) nonGuestPatterns;
      isNonGuest = name: lib.elem name nonGuestUnits || matchesAnyPattern name;
      isGuest = name: lib.elem name guestUnits;

      # (a) escapee — every name in actualUnits that is NEITHER a declared
      #     guest, NOR an explicit non-guest, NOR matched by a pattern. This is
      #     the silent-escape path this check exists to close: a freshly-added
      #     aspect service escapes invariant-2 isolation unnoticed.
      unexpectedGuests = builtins.filter (name: !(isGuest name) && !(isNonGuest name)) actualUnits;

      # (b) stale guest — declared in lib/soyo-guest-units.nix but no longer a
      #     systemd service on soyo. The aspect that introduced the unit went
      #     away; either re-wire it or remove the entry.
      staleGuests = lib.subtractLists actualUnits guestUnits;

      # (c) stale non-guest — explicitly excluded above but no longer a
      #     systemd service on soyo (renamed upstream, dropped by an aspect).
      #     Pattern-based exclusions are open-ended and need no such cleanup;
      #     named entries do.
      staleNonGuests = lib.subtractLists actualUnits nonGuestUnits;

      # (d) double-classified — a name listed both as a guest AND in
      #     nonGuestUnits. A confused invariant: soyo-guest-isolation.nix would
      #     then validate isolation against an entry this file says isn't a
      #     guest. Pick one.
      doubleClassified = lib.intersectLists guestUnits nonGuestUnits;

      # (e) pattern-shadowed guest — a guest name that also matches a
      #     nonGuestPatterns entry. Same confused invariant as (d), but the
      #     pattern side, which intersectLists cannot see:
      #     soyo-guest-isolation still validates its isolation while this
      #     file's isNonGuest claims it is infrastructure. No current pattern
      #     (systemd-*, getty) shadows any current guest, so this is forward
      #     defense against a future widened pattern silently swallowing a
      #     real guest.
      patternShadowedGuests = builtins.filter matchesAnyPattern guestUnits;

      # Negative control: a hypothetical future M4 service must meet none of
      # the lists/patterns, so the catch logic actually fires. If a future
      # edit widens a pattern such that this synthetic name silently passes,
      # the check's harness itself fails — surfacing the regression rather
      # than letting the invariant go quiet. Declared before failureLines
      # because the harness-regression line below references fixtureCaught.
      fixture = "future-m4-service-fixture";
      fixtureCaught = !(isGuest fixture) && !(isNonGuest fixture);

      failureLines =
        map (
          n:
          "unexpected: service '${n}' exists on soyo but is neither in the guest list (lib/soyo-guest-units.nix) nor excluded (modules/parts/soyo-guest-coverage.nix). Add isolation in the aspect that defines it AND register it in lib/soyo-guest-units.nix, OR add it to nonGuestUnits here with a reason."
        ) unexpectedGuests
        ++ map (
          n:
          "stale guest: '${n}' is in lib/soyo-guest-units.nix but is not a systemd service on soyo. Remove it, or re-wire the aspect that should define it."
        ) staleGuests
        ++ map (
          n:
          "stale non-guest: '${n}' is in nonGuestUnits (modules/parts/soyo-guest-coverage.nix) but is not a systemd service on soyo. Remove it."
        ) staleNonGuests
        ++ map (
          n:
          "double-classified: '${n}' appears in BOTH lib/soyo-guest-units.nix (isolated guest) AND nonGuestUnits (modules/parts/soyo-guest-coverage.nix). Pick one."
        ) doubleClassified
        ++ map (
          n:
          "pattern-shadowed guest: '${n}' is in lib/soyo-guest-units.nix but also matches a nonGuestPatterns entry in modules/parts/soyo-guest-coverage.nix. Tighten the pattern, or rename the unit."
        ) patternShadowedGuests
        # Harness self-honesty: the negative-control fixture must remain
        # unclassified — a future pattern-widening that silently swallows it
        # is a regression in the check itself. Reported via failureLines (not a
        # shell branch) so the message is always present when this fires, even
        # when real escapees also produced failureLines above.
        ++
          lib.optional (!fixtureCaught)
            "internal: harness accepted the negative-control fixture '${fixture}' — set arithmetic has narrowed";
    in
    {
      checks.soyo-guest-coverage =
        pkgs.runCommand "soyo-guest-coverage-test"
          {
            failed = if failureLines == [ ] && fixtureCaught then "0" else "1";
            failureText = lib.concatStringsSep "\n" failureLines;
            passAsFile = [ "failureText" ];
          }
          ''
            if [ "$failed" != 0 ]; then
              echo "ERROR: Soyo guest-coverage (deny-by-default) check failed:" >&2
              cat "$failureTextPath" >&2
              exit 1
            fi
            touch "$out"
          '';
    };
}
