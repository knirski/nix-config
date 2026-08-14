# Shared-desk switching aspect: one key combo moves the whole desk to a host.
#
# The desk (Iiyama PL2792Q + Logitech MX Master 2S + K860) is shared between
# zbook (DisplayPort) and ubuntu (HDMI). A switch moves two things, both fully
# automatic:
#
#   1. Keyboard and mouse -- Logitech HID++ change-host. Both devices expose
#      the CHANGE HOST feature {1814}, and each stores one pairing per
#      Easy-Switch channel: channel 1 = zbook's Unifying receiver, channel 2 =
#      ubuntu's. `solaar config <device> change-host <1|2>` hops the device
#      between them. The command rides the CURRENT connection, so it always
#      runs on the machine the devices are attached to right now -- the target
#      receiver never needs a command run on it. That is why no SSH or remote
#      trigger is involved.
#
#   2. Monitor input -- DDC/CI VCP feature 0x60 (Input Source). Any host can
#      set it over the input it drives: zbook over DP, ubuntu over HDMI.
#      `ddcutil capabilities` on this monitor reports exactly three values:
#      0x0f DisplayPort-1, 0x11 HDMI-1, 0x03 DVI-1.
#
# The pairing itself is stored in the receivers and survives reboots, so
# the hop is instant and needs no software on the target machine.
#
# ## One-time pairing (prerequisite)
#
# The combo only moves devices that already hold a pairing with BOTH
# receivers, one per Easy-Switch channel -- and the script selects hosts by
# position, so channel 1 must be zbook and channel 2 ubuntu. Both devices
# are already paired that way. Redo this only for a new device or after a
# factory reset:
#
# 1. Pair the device to zbook's receiver on Easy-Switch channel 1 (the
#    channel it uses while connected here).
# 2. Pair the device to ubuntu's receiver on channel 2, without running
#    anything on ubuntu:
#    a. Plug ubuntu's Unifying receiver into this host.
#    b. Find its hidraw node:
#         grep -l logitech-djreceiver /sys/class/hidraw/hidraw*/device/uevent
#    c. Put the receiver into pairing mode:
#         solaar-cli -D /dev/hidrawX pair
#    d. On the device, press Easy-Switch until channel 2 blinks -- it binds
#       to the receiver on that channel.
#    e. Unplug the receiver and return it to ubuntu.
# 3. Verify from zbook:
#      solaar-cli -D /dev/hidraw0 show "ERGO K860"
#    → CHANGE HOST shows 1:zbook and HOSTS INFO lists both hosts paired;
#    then press Mod4+Home once: both devices should hop to ubuntu.
#
# ## Usage
#
#   Mod4+Insert → desk-switch zbook   (devices to channel 1, DisplayPort)
#   Mod4+Home   → desk-switch ubuntu  (devices to channel 2, HDMI)
#
# Each direction is idempotent and can be pressed from either machine: a
# device that is not on the local receiver is already on the target host, and
# ddcutil reaches the monitor from both inputs.
#
# ## Sources
#
# - Solaar: https://pwr-solaar.github.io/Solaar/
# - ddcutil: https://www.ddcutil.com/
# - VCP feature 0x60 input-source codes: https://www.ddcutil.com/ddc_vcp_features_table/
{
  aspects.homeManager.deskSwitch =
    { pkgs, ... }:
    let
      # writeShellApplication (like git-ssh-sign in modules/parts/ubuntu.nix):
      # runtimeInputs put ddcutil, notify-send and solaar-cli on the script's
      # PATH, so the binding can call the script by its full store path and
      # still resolve its tools no matter what PATH the caller (sway's
      # `sh -c`) provides. It also adds set -euo pipefail.
      deskSwitch = pkgs.writeShellApplication {
        name = "desk-switch";
        runtimeInputs = [
          pkgs.ddcutil
          pkgs.libnotify
          pkgs.solaar
        ];
        text = ''
          # Switch the shared desk to TARGET: hop the MX Master and K860 to
          # the target's receiver, then switch the monitor input. Devices
          # first: if the monitor step fails, input already follows to the
          # target machine, where the combo can be pressed again to retry.
          target=''${1:-}
          case "$target" in
            zbook)  host="1"; vcp="0x0f" ;; # Easy-Switch channel 1 → zbook; DisplayPort-1
            ubuntu) host="2"; vcp="0x11" ;; # Easy-Switch channel 2 → ubuntu; HDMI-1
            *)
              echo "usage: desk-switch <zbook|ubuntu>" >&2
              exit 2
              ;;
          esac

          # The Unifying receiver(s) attached to this host. solaar-cli -D
          # talks to one directly, no daemon needed. Both hosts normally have
          # exactly one; the loop tolerates a second (e.g. while re-pairing).
          receivers=""
          for h in /sys/class/hidraw/hidraw*; do
            if grep -q logitech-djreceiver "$h/device/uevent" 2>/dev/null; then
              receivers="$receivers /dev/''${h##*/}"
            fi
          done

          # change-host rides the current connection, so it only reaches a
          # device attached to THIS host. A device that is not here is
          # already on the target host -- that is success, not failure.
          # A device that IS here but refuses the switch is a real error.
          moved=""
          failed=""
          for dev in "MX Master" "ERGO K860"; do
            for r in $receivers; do
              if solaar-cli -D "$r" config "$dev" change-host "$host" >/dev/null 2>&1; then
                moved="$moved $dev"
                break
              elif solaar-cli -D "$r" show "$dev" >/dev/null 2>&1; then
                failed="$failed $dev"
              fi
            done
          done

          if [ -n "$failed" ]; then
            notify-send -a desk-switch -u critical "Desk switch to $target: device error" \
              "Could not move:$failed. Monitor input will still be switched."
          elif [ -z "$receivers" ]; then
            notify-send -a desk-switch -u critical "Desk switch to $target: no receiver" \
              "No Logitech Unifying receiver found on this host -- devices cannot follow."
          fi

          if ddcutil setvcp 0x60 "$vcp"; then
            exit 0
          fi
          rc=$?
          notify-send -a desk-switch -u critical "Desk switch to $target failed" \
            "Monitor unreachable via DDC/CI (exit $rc). Is it on and is the cable connected?"
          exit "$rc"
        '';
      };
    in
    {
      home.packages = [
        pkgs.ddcutil
        pkgs.libnotify
        pkgs.solaar
        deskSwitch
      ];

      # Both hosts use the shared sway aspect, whose modifier is Mod4. The
      # binding lives here (not in that aspect) so this desk capability can be
      # toggled per host without the whole sway aspect.
      wayland.windowManager.sway.config.keybindings = {
        "Mod4+Insert" = "exec ${deskSwitch}/bin/desk-switch zbook";
        "Mod4+Home" = "exec ${deskSwitch}/bin/desk-switch ubuntu";
      };
    };
}
