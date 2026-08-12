# NixOS aspect: boot the USB-attached Windows 11 (Windows To Go) SSD in a
# QEMU/KVM VM.
#
# `win-usb` is a native-Windows escape hatch from NixOS: when the KIOXIA USB
# SSD — a full Windows 11 LTSC install, created by running Windows Setup in
# this same VM with the disk passed through — is plugged in, one command
# boots it in a VM without rebooting the machine.
#
# `win-usb-image` snapshots the SSD (partition table + per-partition images,
# NTFS-aware and zstd-compressed) so a pristine installation can be restored
# later. Both commands share the disk-detection preamble below, so they can
# never drift apart on which disk they consider "the" USB SSD.
#
# Why SATA (ich9-ahci) instead of usb-storage: Windows Setup refuses disks on
# a USB bus ("Setup does not support configuration of or installation to
# disks connected through a USB port"), so the install was done with the disk
# on SATA. Booting the finished system is bus-agnostic — UEFI only reads the
# ESP, and Windows' boot stack includes the inbox usbstor driver — which is
# also why the same SSD boots on real hardware (F9 boot menu).
#
# Full usage and restore instructions: docs/win-usb.md
{
  aspects.nixos.win2go =
    { pkgs, ... }:
    let
      # Shared preamble: root re-exec, SSD detection (edit the model matcher
      # if the enclosure/SSD ever changes), and the two safety guards.
      # Both scripts must list every tool they use in runtimeInputs below —
      # the repository's shell-boundaries check rejects unchecked
      # writeShellScript usage.
      preamble = ''
        set -euo pipefail

        # Raw /dev/sdX access needs root.
        if [ "$(id -u)" -ne 0 ]; then
          exec sudo -E "$0" "$@"
        fi

        # --- locate the USB SSD (exactly one; by-id for stable identity) ----
        # The guest gets raw write access to this disk: refuse ambiguity
        # instead of guessing when more than one KIOXIA USB disk is attached.
        candidates="$(lsblk -dno NAME,MODEL,TRAN | awk 'tolower($0) ~ /kioxia/ && tolower($NF) == "usb" { print $1 }')"
        count="$(printf '%s\n' "$candidates" | grep -c . || true)"
        if [ "$count" -ne 1 ]; then
          echo "error: expected exactly one KIOXIA USB SSD, found $count." >&2
          lsblk -dno NAME,MODEL,TRAN | awk 'tolower($NF) == "usb" { print "  " $0 }' >&2
          exit 1
        fi
        name="$(printf '%s\n' "$candidates" | head -1)"
        dev="/dev/$name"

        # Prefer the /dev/disk/by-id link: the kernel may rename the node on
        # hotplug, while the by-id name stays tied to the device.
        byid=""
        for link in /dev/disk/by-id/usb-*; do
          [ -e "$link" ] || continue
          if [ "$(readlink -f "$link")" = "/dev/$name" ]; then
            byid="$link"
            break
          fi
        done
        if [ -n "$byid" ]; then
          dev="$byid"
        fi

        # Never touch a disk the host has mounted (concurrent NTFS writes corrupt).
        if lsblk -no MOUNTPOINTS "$dev" | grep -q .; then
          echo "error: $dev has mounted partitions; unmount first: sudo umount ''${dev}*" >&2
          exit 1
        fi

        # Refuse to double-attach the same disk (two VMs would corrupt it).
        if pgrep -f "qemu-system-x86_64.*$dev" >/dev/null 2>&1; then
          echo "error: a VM already has $dev attached — close it first." >&2
          exit 1
        fi

        # Exclusive lock: two invocations racing past the pgrep check would
        # both touch the raw disk. Held for the whole run (fd 9 survives the
        # exec below); pgrep stays as a secondary guard for VMs started
        # outside this tool.
        lock="/run/lock/win2go-$name.lock"
        exec 9>"$lock"
        flock -n 9 || {
          echo "error: another win-usb/win-usb-image is already using $dev." >&2
          exit 1
        }
      '';
    in
    {
      environment.systemPackages = [
        pkgs.qemu
        # ntfsclone (NTFS-aware imaging) and zstd (compression for images).
        pkgs.ntfs3g
        pkgs.zstd
        (pkgs.writeShellApplication {
          name = "win-usb";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gawk
            pkgs.glibc.bin # getent (resolve SUDO_USER's home)
            pkgs.gnugrep
            pkgs.procps # pgrep
            pkgs.qemu
            pkgs.sudo
            pkgs.util-linux # lsblk
          ];
          text = ''
            ${preamble}

            ovmf_code=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd
            ovmf_vars_template=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd

            # --- persistent UEFI vars -------------------------------------------
            # Windows Setup wrote a "Windows Boot Manager" entry here during
            # install; keep that file so the VM boots the disk directly. If it
            # is ever deleted, OVMF falls back to the ESP's \EFI\BOOT\BOOTX64.EFI
            # and the disk still boots.
            if [ -n "''${SUDO_USER:-}" ]; then
              vars_dir="$(getent passwd "$SUDO_USER" | cut -d: -f6)/.local/share/win2go"
            else
              vars_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/win2go"
            fi
            vars="$vars_dir/OVMF_VARS.fd"
            if [ ! -e "$vars" ]; then
              install -d "$vars_dir"
              cp "$ovmf_vars_template" "$vars"
            fi

            # --- assemble the VM ------------------------------------------------
            # qemu args use comma syntax; keep every element quoted so it
            # stays a single array element.
            qemu_args=(
              "-machine" "q35,accel=kvm" "-cpu" "host" "-smp" "''${WIN_USB_SMP:-8}" "-m" "''${WIN_USB_MEM:-8G}"
              "-drive" "if=pflash,format=raw,readonly=on,file=$ovmf_code"
              "-drive" "if=pflash,format=raw,file=$vars"
              "-device" "ich9-ahci,id=sata"
              "-drive" "file=$dev,format=raw,if=none,id=winusb"
              "-device" "ide-hd,drive=winusb,bus=sata.2"
              "-netdev" "user,id=net0" "-device" "e1000e,netdev=net0"
              "-display" "gtk"
            )
            case "''${1:-}" in
              --iso)
                [ -f "''${2:-}" ] || { echo "error: ISO not found: ''${2:-}" >&2; exit 1; }
                qemu_args+=(-drive "file=$2,media=cdrom,readonly=on")
                ;;
              "") ;;
              *) echo "usage: win-usb [--iso /path/to/windows.iso]" >&2; exit 2 ;;
            esac

            exec qemu-system-x86_64 "''${qemu_args[@]}"
          '';
        })
        (pkgs.writeShellApplication {
          name = "win-usb-image";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gawk
            pkgs.glibc.bin # getent
            pkgs.gnugrep
            pkgs.ntfs3g # ntfsclone
            pkgs.procps # pgrep
            pkgs.sudo
            pkgs.util-linux # lsblk, blkid, sfdisk
            pkgs.zstd
          ];
          text = ''
            ${preamble}

            # --- destination -----------------------------------------------------
            # ~/ is ephemeral on this host; snapshots belong on the NAS.
            dest_dir="''${1:-}"
            if [ -z "$dest_dir" ]; then
              echo "error: no destination given." >&2
              echo "usage: win-usb-image <dest-dir>   (e.g. a NAS path)" >&2
              exit 1
            fi
            stamp="$(date +%Y%m%d-%H%M%S)"
            out="$dest_dir/win2go-$stamp"
            mkdir -p "$out"

            echo "imaging $dev -> $out (leave the SSD idle, do not attach it to a VM)"

            # Exact partition table, so restore can reproduce the layout 1:1.
            sfdisk -d "$dev" > "$out/parttable.txt"

            # Per-partition images: ntfsclone for NTFS (used clusters only, so
            # the image is tens of GB instead of the disk's full 954 GB); plain
            # dd for ESP/MSR (small, no filesystem tools needed).
            {
              echo "# Restore this image on the NixOS host (root):"
              echo "#   sudo sfdisk $dev < parttable.txt"
              echo "# then, in partition order:"
            } > "$out/restore-notes.txt"

            for part in $(lsblk -nlo NAME "$dev" | tail -n +2); do
              p="/dev/$part"
              fstype="$(blkid -s TYPE -o value "$p" || true)"
              case "$fstype" in
                ntfs)
                  echo "  $p (ntfs): ntfsclone + zstd"
                  ntfsclone -s -o - "$p" | zstd -q -f -o "$out/$part.ntfsclone.zst"
                  echo "  zstd -dc $part.ntfsclone.zst | sudo ntfsclone -r -o $p -" >> "$out/restore-notes.txt"
                  ;;
                *)
                  echo "  $p (''${fstype:-none}): dd + zstd"
                  dd if="$p" bs=4M status=none | zstd -q -f -o "$out/$part.raw.zst"
                  echo "  zstd -dc $part.raw.zst | sudo dd of=$p bs=4M status=progress" >> "$out/restore-notes.txt"
                  ;;
              esac
            done

            # The script runs as root; hand the image back to the invoking user
            # so they can manage (or delete) it without sudo.
            if [ -n "''${SUDO_USER:-}" ]; then
              chown -R "$SUDO_USER" "$out"
            fi

            echo "done. contents:"
            du -sh "$out"/* | sort -rh
            echo "restore steps: $out/restore-notes.txt (also in docs/win-usb.md)"
          '';
        })
      ];
    };
}
