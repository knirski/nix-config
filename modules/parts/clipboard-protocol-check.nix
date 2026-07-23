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
    in
    {
      checks.clipboard-protocols = runKvmTest {
        name = "clipboard-protocols";

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

          machine.succeed("test -S ${runtimeDir}/wayland-test")
        '';
      };
    };
}
