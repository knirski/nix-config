{
  aspects.nixos.laptop =
    { lib, pkgs, ... }:
    {
      services = {
        power-profiles-daemon.enable = true;
        thermald.enable = true;
        upower.enable = true;
        fwupd.enable = true;
      };

      # When the Thunderbolt dock is unplugged and reconnected, the RTL8153
      # Ethernet interface gets a new USB path. NetworkManager may not
      # properly re-match its connection profile or re-evaluate routing/DNS,
      # leaving the system with "connected" but no usable data path.
      #
      # This dispatcher script fires on any "up" event for physical ethernet
      # interfaces (en*) and reapplies the device + flushes DNS — same idea
      # as the s2idle resumeCommands below, but triggered on hotplug too.
      networking.networkmanager.dispatcherScripts = [
        {
          source = "${
            pkgs.writeShellApplication {
              name = "nm-dock-hotplug-fix";
              runtimeInputs = [
                pkgs.networkmanager
                pkgs.systemd
              ];
              text = ''
                if [ "$2" = "up" ] && [[ "$1" == en* ]]; then
                  nmcli device reapply "$1" 2>/dev/null || true
                  resolvectl flush-caches 2>/dev/null || true
                fi
              '';
            }
          }/bin/nm-dock-hotplug-fix";
          type = "basic";
        }
      ];

      # CPU frequency governor is managed dynamically by power-profiles-daemon
      # (controlled by DMS power profile settings), not hardcoded here.
      # Powertop applies power-saving tunings at boot via --auto-tune;
      # Logitech receiver USB autosuspend is handled immutably via usbcore.quirks.
      powerManagement = {
        powertop.enable = true;
        # After s2idle resume, NetworkManager often reports "connected" but
        # the actual data path (DNS resolution, interface state, route table)
        # is broken — common with USB-C dock Ethernet and s2idle on laptops.
        #
        # Previously this restarted NetworkManager entirely, but DMS (Dank
        # Material Shell) connects to NM via D-Bus and has no reconnection
        # logic — once NM restarts, DMS's signal subscriptions are permanently
        # lost and it shows "not connected" even when WiFi is working.
        # Instead of restarting NM, reload connection profiles, reapply the
        # active devices (this pushes DNS servers to systemd-resolved, which
        # gets lost on s2idle), and flush the DNS cache — sufficient to fix
        # the stale data path without breaking D-Bus consumers.
        resumeCommands = ''
          ${pkgs.networkmanager}/bin/nmcli connection reload 2>/dev/null || true
          for dev in $(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE device status | ${pkgs.gnugrep}/bin/grep ':ethernet\|:wifi' | ${pkgs.coreutils}/bin/cut -d: -f1); do
            ${pkgs.networkmanager}/bin/nmcli device reapply "$dev" 2>/dev/null || true
          done
          ${pkgs.systemd}/bin/resolvectl flush-caches 2>/dev/null || true
        '';
      };

      # Intel P-State driver (better power management on 12th/13th gen)
      boot.kernelParams = [
        "intel_pstate=active"
        # USB quirks at the USB-core level, applied at device enumeration
        # before any driver binds — immutable, immune to powertop --auto-tune.
        # https://docs.kernel.org/admin-guide/kernel-parameters.html
        # "b" = USB_QUIRK_RESET_RESUME: Logitech Unifying (c52b) and Bolt
        # (c532) receivers stutter after s2idle resume; resetting the device
        # on resume re-initializes the radio cleanly.
        # "j" = USB_QUIRK_IGNORE_REMOTE_WAKEUP: the dock's Realtek RTL8153
        # LAN chip raises a remote wake on s2idle entry (link-state change),
        # re-waking the machine ~3s after suspend. A udev rule alone cannot
        # fix this — it races the r8152 driver, which re-enables wakeup in
        # its probe — so kill the capability at the USB core.
        "usbcore.quirks=046d:c52b:b,046d:c532:b,0bda:8153:j"
        # Disable NVMe APST (autonomous power-state transitions): the XPG
        # S70 Blade's firmware can fail to wake from a low-power state after
        # s2idle, wedging the PCIe link. The whole disk then hangs, btrfs
        # remounts read-only after command timeouts, and only a cold reboot
        # recovers. APST saves a few watts at idle; on this firmware the
        # stability risk is not worth it. (The module parameter only applies
        # at controller init — see disable-nvme-apst.service below for the
        # per-controller runtime re-assert.)
        # https://docs.kernel.org/admin-guide/kernel-parameters.html
        "nvme_core.default_ps_max_latency_us=0"
      ];

      # Laptop lid switch handling
      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "lock";
        HandleLidSwitchDocked = "ignore";
      };

      # Disable USB wake for the dock's Realtek RTL8153 Ethernet adapter.
      # On s2idle (S0ix), link-state changes from the >1Gbps LAN chip
      # trigger an immediate re-wake after suspend entry, even when the
      # cable is idle. Only the dock LAN is targeted, not internal USB.
      # Belt-and-suspenders: the authoritative fix is the 0bda:8153:j
      # usbcore quirk above (this rule alone races the r8152 driver probe,
      # which re-enables wakeup).
      services.udev.extraRules = lib.mkAfter ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", ATTR{power/wakeup}="disabled"
      '';

      # Disable Thunderbolt host controller and DMA wake sources before every
      # suspend. /proc/acpi/wakeup is a toggle — writing a device name
      # switches it on/off — so we only write if currently enabled.
      # On s2idle, the HP Thunderbolt dock (TDM0/TDM1) fires an immediate
      # wake event on suspend entry, overriding the RTL8153 udev fix.
      systemd.services.disable-thunderbolt-wake = {
        description = "Disable Thunderbolt wake sources before suspend";
        before = [ "systemd-suspend.service" ];
        wantedBy = [ "sleep.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          for dev in TXHC TDM0 TDM1; do
            if grep -q "^''${dev}[[:space:]]\+S[0-9][[:space:]]\+\*enabled" /proc/acpi/wakeup; then
              echo "$dev" > /proc/acpi/wakeup
            fi
          done
        '';
      };

      # The nvme_core.default_ps_max_latency_us=0 kernel param above disables
      # APST at controller init, but it cannot be changed for a running
      # controller — powertop's --auto-tune writes the module parameter sysfs
      # file (observed 100000 µs) with no effect on the already-initialized
      # controller. The effective runtime knob is each controller's PM QoS
      # latency tolerance node, so re-assert the disable per controller after
      # powertop has run and again on every resume (sleep.target) — the
      # failure mode this prevents is tied to s2idle resumes.
      systemd.services.disable-nvme-apst = {
        description = "Disable NVMe APST (re-assert per controller after powertop and on resume)";
        after = [
          "powertop.service"
          "systemd-suspend.service"
          "systemd-hibernate.service"
        ];
        wantedBy = [
          "multi-user.target"
          "sleep.target"
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          for qos in /sys/class/nvme/nvme[0-9]*/power/pm_qos_latency_tolerance_us; do
            [ -w "$qos" ] || continue
            echo 0 > "$qos"
          done
        '';
      };
    };
}
