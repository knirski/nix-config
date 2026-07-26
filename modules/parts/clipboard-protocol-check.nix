# Protocol-level clipboard coverage. The production desktop uses Sway and DMS,
# so the test runs the same compositor in wlroots' headless backend. It needs no
# GPU, greeter, or physical session and deliberately does not start DMS: that is
# a separate desktop-integration concern, while this check covers compositor/
# client protocol behavior.
_: {
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      runKvmTest = import ../../lib/testing/run-kvm-test.nix { inherit pkgs; };
      kvmChecks = import ../../lib/testing/kvm-checks.nix;
      runtimeDir = "/tmp/clipboard-wayland-runtime";
      compositorEnv = "XDG_RUNTIME_DIR=${runtimeDir}";
      clientEnv = "XDG_RUNTIME_DIR=${runtimeDir} WAYLAND_DISPLAY=wayland-test";
      escapePythonString = value: lib.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] value;
      asClient = command: escapePythonString "env ${clientEnv} sh -c ${lib.escapeShellArg command}";
      waitForOffer = ''
        wait_for_offer() {
          selection="$1"
          mime="$2"
          attempts=0
          while [ "$attempts" -lt 20 ]; do
            if [ "$selection" = primary ]; then
              types=$(timeout 1 wl-paste --primary --list-types 2>/dev/null || true)
            else
              types=$(timeout 1 wl-paste --list-types 2>/dev/null || true)
            fi
            if printf '%s\n' "$types" | grep -Fqx "$mime"; then
              return 0
            fi
            attempts=$((attempts + 1))
            sleep 0.1
          done
          return 1
        }
      '';
      regularClipboard = ''
        set -eu
        printf 'regular clipboard ✓' | wl-copy --paste-once --type 'text/plain;charset=utf-8' >/tmp/wl-copy.log 2>&1 &
        copy_pid=$!
        ${waitForOffer}
        wait_for_offer regular 'text/plain;charset=utf-8'
        test "$(timeout 5 wl-paste -n)" = 'regular clipboard ✓'
        wait "$copy_pid"
      '';
      primaryClipboard = ''
        set -eu
        ${waitForOffer}
        # wlroots' data-control selection handling races when two clients call
        # set_selection at nearly the same instant: the loser is left with no
        # owner and wl-paste reports "Nothing is copied". So establish the two
        # selections one at a time -- regular first, then primary once regular's
        # offer is actually visible. This serialises only the *set*, not the
        # ownership: both selections stay owned simultaneously afterwards, so
        # PRIMARY independence is still exercised for real.
        #
        # --foreground keeps each wl-copy as the genuine selection owner. The
        # default double-forks and the launched process exits the moment the
        # selection is set, which would make the trailing `wait` reap an
        # already-dead launcher instead of the real paste-once owner.
        printf regular | wl-copy --foreground --paste-once &
        regular_pid=$!
        wait_for_offer regular text/plain
        printf primary | wl-copy --foreground --paste-once --primary &
        primary_pid=$!
        wait_for_offer primary text/plain
        # Both selections are held at once: re-confirm regular survived primary
        # taking ownership, proving simultaneous ownership before any paste
        # consumes an owner.
        wait_for_offer regular text/plain
        # Each paste-once read serves once and lets that owner exit. PRIMARY must
        # still read back untouched after the regular selection was consumed.
        test "$(timeout 5 wl-paste -n)" = regular
        test "$(timeout 5 wl-paste --primary -n)" = primary
        wait "$regular_pid" "$primary_pid"
      '';
      binaryClipboard = ''
        set -eu
        printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' | base64 -d > /tmp/clipboard-image
        expected_hash=$(sha256sum /tmp/clipboard-image | cut -d ' ' -f1)
        wl-copy --paste-once --type image/png < /tmp/clipboard-image >/tmp/wl-copy.log 2>&1 &
        copy_pid=$!
        ${waitForOffer}
        wait_for_offer regular image/png
        test "$(timeout 5 wl-paste --type image/png | sha256sum | cut -d ' ' -f1)" = "$expected_hash"
        wait "$copy_pid"
      '';
      clearClipboard = ''
        set -eu
        printf clearable | wl-copy --paste-once >/tmp/wl-copy.log 2>&1 &
        copy_pid=$!
        ${waitForOffer}
        wait_for_offer regular text/plain
        wl-copy --clear
        ! timeout 5 wl-paste -n 2>/dev/null
        kill -KILL "$copy_pid" 2>/dev/null || true
      '';
      # Bridge subtest: re-derive the same `clipboard-bridge` script the
      # sway.nix aspect builds, then drive it from `wl-paste --watch` in
      # both directions. This is the test that justifies the production
      # systemd service pair: it proves the data-control protocol's
      # `--watch` codepath actually delivers new offers to a long-lived
      # subscriber, not just the `--paste-once` codepath the four
      # protocol-level subtests above exercise.
      #
      # The script is rebuilt here verbatim (with the same shape as
      # `modules/home/sway.nix`) so this test stays self-contained: it
      # does not depend on the home-manager activation package, the
      # NixOS service unit, or the `services.xserver.videoDrivers`
      # configuration that the production closure carries.
      bridgeBinary = pkgs.writeShellApplication {
        name = "clipboard-bridge";
        runtimeInputs = [ pkgs.wl-clipboard ];
        # Mirror the production bridge verbatim so this test exercises the
        # same shell code that runs in the user systemd service. Drift here
        # would silently invalidate the KVM check.
        text = ''
          set -euo pipefail
          text=$(cat && printf x)
          text=''${text%x}
          opts=()
          if [ "''${1:-}" = "--to-primary" ]; then
            opts+=(--primary)
          fi
          [ -n "$text" ] || exit 0
          current=$(wl-paste "''${opts[@]}" 2>/dev/null && printf x || true)
          current=''${current%x}
          [ "$text" != "$current" ] || exit 0
          printf %s "$text" | wl-copy "''${opts[@]}"
        '';
      };
      watchBridge = ''
        set -eu
        # Run the same bidirectional bridge production uses, on top of the
        # headless Sway session. Two `wl-paste --watch` subscribers, one
        # per direction; each is launched *individually* (not in parallel)
        # because wlroots' data-control manager only delivers the
        # `selection` event to the most-recently-bound data device per
        # selection, and parallel `--watch` subscribers race for that
        # binding. Production runs the two as separate systemd user
        # services; here we just exercise the per-direction codepath.
        BRIDGE_LOG=/tmp/bridge-watch.log

        # Direction 1: PRIMARY -> CLIPBOARD. Subscriber watches PRIMARY.
        wl-paste --primary --type text --watch ${bridgeBinary}/bin/clipboard-bridge --to-clipboard \
          >"$BRIDGE_LOG" 2>&1 &
        p2c_pid=$!
        # Give wl-paste a moment to bind before mutating the selection.
        sleep 0.5
        # Drive a PRIMARY selection.
        printf 'bridge test from primary' | wl-copy --foreground --primary &
        p_owner=$!
        # Wait for the bridge to mirror it into CLIPBOARD.
        attempts=0
        while [ "$attempts" -lt 30 ]; do
          if [ "$(timeout 1 wl-paste -n 2>/dev/null || true)" = 'bridge test from primary' ]; then
            break
          fi
          attempts=$((attempts + 1))
          sleep 0.1
        done
        test "$attempts" -lt 30 || { echo 'PRIMARY -> CLIPBOARD mirror did not land' >&2; kill "$p2c_pid" 2>/dev/null; exit 1; }
        kill -KILL "$p_owner" 2>/dev/null || true
        # Tear down the subscriber before launching the next direction.
        kill "$p2c_pid" 2>/dev/null || true
        wait "$p2c_pid" 2>/dev/null || true
        # Sanity-check the watch log captured the forwarded payload.
        test -s "$BRIDGE_LOG" || { echo 'PRIMARY -> CLIPBOARD subscriber produced no output' >&2; exit 1; }
        grep -F 'bridge test from primary' "$BRIDGE_LOG"
        # Reset the regular clipboard so it doesn't pollute the second
        # direction.
        wl-copy --clear

        # Direction 2: CLIPBOARD -> PRIMARY. Subscriber watches CLIPBOARD.
        wl-paste --type text --watch ${bridgeBinary}/bin/clipboard-bridge --to-primary \
          >"$BRIDGE_LOG" 2>&1 &
        c2p_pid=$!
        sleep 0.5
        # Drive a CLIPBOARD copy.
        printf 'bridge test from clipboard' | wl-copy --foreground &
        c_owner=$!
        # Wait for the bridge to mirror it into PRIMARY.
        attempts=0
        while [ "$attempts" -lt 30 ]; do
          if [ "$(timeout 1 wl-paste --primary -n 2>/dev/null || true)" = 'bridge test from clipboard' ]; then
            break
          fi
          attempts=$((attempts + 1))
          sleep 0.1
        done
        test "$attempts" -lt 30 || { echo 'CLIPBOARD -> PRIMARY mirror did not land' >&2; kill "$c2p_pid" 2>/dev/null; exit 1; }
        kill -KILL "$c_owner" 2>/dev/null || true
        kill "$c2p_pid" 2>/dev/null || true
        wait "$c2p_pid" 2>/dev/null || true
        test -s "$BRIDGE_LOG" || { echo 'CLIPBOARD -> PRIMARY subscriber produced no output' >&2; exit 1; }
        grep -F 'bridge test from clipboard' "$BRIDGE_LOG"
      '';
    in
    {
      checks.${kvmChecks.clipboardProtocols} = runKvmTest {
        name = kvmChecks.clipboardProtocols;

        nodes.machine = _: {
          environment.systemPackages = [
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.wl-clipboard
            # Keep the compositor explicit: this check must not rely on the
            # main desktop closure making Sway available.
            pkgs.sway
          ];

          system.stateVersion = "26.05";
        };

        testScript = ''
          machine.start()
          machine.wait_for_unit("multi-user.target")
          machine.succeed("command -v sway")

          # Keep compositor and clients in one private runtime directory. The
          # protocol does not depend on account switching, so this keeps the
          # test focused on protocol behavior rather than PAM/session cleanup.
          machine.succeed("install -d -m 700 ${runtimeDir}")

          machine.succeed(
              "env ${compositorEnv} WLR_BACKENDS=headless WLR_RENDERER=pixman "
              "WLR_LIBINPUT_NO_DEVICES=1 SWAY_UNSUPPORTED_GPU=1 "
              "sway --debug --config /dev/null >/tmp/sway.log 2>&1 &"
          )
          machine.wait_until_succeeds(
              "grep -F 'Running compositor on wayland display' /tmp/sway.log"
          )
          machine.wait_until_succeeds(
              "find ${runtimeDir} -maxdepth 1 -type s -name 'wayland-*' -print | grep -q ."
          )
          # Sway chooses its server socket automatically. Give clients a
          # stable name without assuming whether this run selected wayland-0
          # or wayland-1.
          machine.succeed(
              "socket=$(find ${runtimeDir} -maxdepth 1 -type s -name 'wayland-*' -print -quit); "
              "ln -s $(basename \"$socket\") ${runtimeDir}/wayland-test"
          )

          with subtest("regular clipboard preserves text and MIME type"):
              machine.succeed("${asClient regularClipboard}")

          with subtest("PRIMARY remains independent"):
              machine.succeed("${asClient primaryClipboard}")

          with subtest("binary MIME data is not converted to text"):
              machine.succeed("${asClient binaryClipboard}")

          with subtest("regular clipboard can be cleared"):
              machine.succeed("${asClient clearClipboard}")

          with subtest("bidirectional PRIMARY <-> CLIPBOARD bridge via wl-paste --watch"):
              machine.succeed("${asClient watchBridge}")

          machine.succeed("test -S ${runtimeDir}/wayland-test")
        '';
      };
    };
}
