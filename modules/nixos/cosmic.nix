{
  # This module depends on package overrides in the host assembler:
  #   - cosmic-ext-* packages come from the stable nixpkgs input overlay
  #     (not available in nixpkgs-unstable used as the primary channel).
  # Future hosts toggling this aspect must replicate that overlay.
  aspects.nixos.cosmic =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      services = {
        desktopManager.cosmic.enable = true;
        displayManager.cosmic-greeter.enable = true;
      };

      environment.systemPackages = with pkgs; [
        cosmic-ext-applet-external-monitor-brightness
        cosmic-ext-tweaks
      ];

      # Freeze cosmic-comp before NVIDIA's VT switch (chvt 63) in
      # nvidia-sleep.sh suspend. SIGSTOP is the standard Wayland compositor
      # suspend pattern — it prevents any DRM ioctl from being in-flight
      # when the VT switch triggers cosmic-comp's udev handler.
      # This must be ExecStartPre on nvidia-suspend.service, not
      # powerDownCommands (sleep-actions ExecStart), because they run
      # in parallel and nvidia-sleep.sh's chvt 63 races ahead of SIGSTOP.
      systemd.services.nvidia-suspend = lib.mkIf config.lanAppliance.services.nvidia.enable {
        serviceConfig.ExecStartPre = [
          ""
          (pkgs.writeShellScript "freeze-cosmic-comp" ''
            set -e
            PID=$(pidof cosmic-comp 2>/dev/null || true)
            if [ -n "$PID" ]; then
              kill -STOP "$PID" 2>/dev/null || true
            fi
          '')
        ];
      };

      # Unfreeze cosmic-comp and re-probe displays after resume.
      # The udev trigger runs after SIGCONT so cosmic-comp is awake
      # to process the hotplug uevents.
      systemd.services.nvidia-resume = lib.mkIf config.lanAppliance.services.nvidia.enable {
        serviceConfig.ExecStartPost = [
          ""
          (pkgs.writeShellScript "resume-cosmic-comp" ''
            set -e

            # Wait for USB-C dock re-enumeration. On s2idle (S0ix), the
            # GPU resumes before the dock USB hub re-enumerates, so
            # connector status reads "disconnected" if we probe too
            # early. 2s is enough for the dock to settle.
            ${pkgs.coreutils}/bin/sleep 2

            # SIGCONT the compositor so it can process events.
            PID=$(pidof cosmic-comp 2>/dev/null || true)
            if [ -n "$PID" ]; then
              kill -CONT "$PID" 2>/dev/null || true
            fi

            # Find all external connectors on the NVIDIA card (card0)
            # and poll until they re-appear or 10s pass.
            CONNECTORS=""
            for connector in /sys/class/drm/card0-*/status; do
              [ -f "$connector" ] || continue
              name=$(basename "$(dirname "$connector")")
              case "$name" in
                card0-eDP-*|card0-LVDS-*) continue ;;
              esac
              dir="$(dirname "$connector")"
              CONNECTORS="$CONNECTORS $dir"
            done

            for i in $(${pkgs.coreutils}/bin/seq 1 10); do
              ALL=true
              for dir in $CONNECTORS; do
                if [ "$(cat "$dir/status" 2>/dev/null)" != "connected" ]; then
                  ALL=false
                fi
              done
              $ALL && break
              ${pkgs.coreutils}/bin/sleep 1
            done

            # Trigger a udev 'change' event on each NVIDIA connector
            # to simulate a hotplug uevent. cosmic-comp re-probes
            # display state when it receives these.
            for dir in $CONNECTORS; do
              ${pkgs.systemd}/bin/udevadm trigger --action=change "$dir" 2>/dev/null || true
            done
          '')
        ];
      };

    };
}
