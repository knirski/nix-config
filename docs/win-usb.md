# Windows on USB SSD (win-usb)

zbook carries a full Windows 11 IoT Enterprise LTSC 2024 installation on a
KIOXIA USB SSD (Windows-To-Go style). `win-usb` boots the SSD in a QEMU/KVM VM from NixOS — no reboot needed — and
`win-usb-image` snapshots the SSD so a pristine installation can be restored
later. The VM's NVRAM state (`~/.local/share/win2go/`) is persisted across
reboots via the zbook persistence inventory (`lib/zbook-persistence.nix`);
everything else under `~` lives on the ephemeral root and is wiped each boot.
Disk images therefore belong on the NAS — `win-usb-image` requires an
explicit destination argument.

The same SSD also boots on real hardware via the F9 boot menu, which is the
intended way to run GPU-accelerated or latency-sensitive Windows workloads;
the VM is the convenient path for occasional native-Windows tasks.

## Quick start

Plug in the KIOXIA USB SSD, then:

```sh
win-usb                 # or: just win-usb — boot the USB Windows in a VM
win-usb --iso ~/Downloads/windows.iso   # reinstall mode (attaches installer media)
win-usb-image /mnt/nas/win2go-images    # snapshot the SSD; destination is required
                                        # (pass a durable path — ~/ is ephemeral)
```

Optional tweaks: `WIN_USB_SMP=4 WIN_USB_MEM=12G win-usb` overrides the default
8 vCPUs / 8 GB RAM.

## How it works

Everything lives in the `aspects.nixos.win2go` module
(`modules/nixos/win2go.nix`, enabled on zbook in `modules/parts/zbook.nix`).
Both commands share a preamble that:

- re-execs via `sudo -E` (raw disk access; passwordless sudo on zbook) while
  preserving the Wayland environment so the GTK window can open;
- locates the SSD by model (`KIOXIA` + `TRAN=usb` — edit the matcher if the
  enclosure/SSD ever changes) and requires **exactly one** match: zero means
  unplugged, several means ambiguity, and both are errors rather than guesses;
- resolves the stable `/dev/disk/by-id` path for the matched disk, so a
  hotplug rename cannot redirect the VM or the imager to a different device;
- refuses to run while any partition is mounted, while another VM already
  has the disk attached, or while another `win-usb`/`win-usb-image` holds the
  disk's `flock` (concurrent NTFS access corrupts).

Key design decisions:

- **SATA, not USB, attachment.** Windows Setup refuses disks on a USB bus
  ("Setup does not support configuration of or installation to disks
  connected through a USB port"), so the disk is presented as `ich9-ahci`
  SATA. Booting the finished system is bus-agnostic: UEFI only reads the ESP,
  and Windows' boot stack includes the inbox `usbstor` driver — which is also
  why the same SSD boots on real hardware.
- **Persistent UEFI vars.** The VM keeps its NVRAM in
  `~/.local/share/win2go/OVMF_VARS.fd` (created from the OVMF template on
  first run). The "Windows Boot Manager" entry that Windows Setup wrote there
  makes the VM boot the disk directly. If the file is deleted, OVMF falls
  back to the ESP's `\EFI\BOOT\BOOTX64.EFI` and the disk still boots.
- **Exclusive access.** The disk is matched by model and must be the only
  KIOXIA USB disk attached; the stable `/dev/disk/by-id` identity is used for
  attach and imaging, and a `flock` on `/run/lock/win2go-<disk>.lock`
  (per disk, held for the whole run) guarantees only one of `win-usb` /
  `win-usb-image` touches the disk at a time.
- **Networking** is user-mode NAT (`e1000e`), so Windows has internet in the
  VM but no inbound access.

## Why this SSD exists (one-time creation)

The installation was created by running the Windows 11 LTSC ISO's Setup
inside this same VM with the disk passed through as SATA:

- IoT Enterprise LTSC 2024 is the relaxed SKU — no TPM, Secure Boot, or CPU
  enforcement, so plain OVMF firmware suffices.
- After Setup's first reboot, the VM tried the DVD first; the "Press any key
  to boot from CD" prompt re-enters Setup (which resumes the install), while
  ignoring it boots from the disk (which also resumes). Both paths work.
- If the VM ever boots from the disk instead of the CD unexpectedly, reset
  the NVRAM: delete `~/.local/share/win2go/OVMF_VARS.fd` (a fresh copy is
  made from the template on next run).

## Snapshot and restore

`win-usb-image <dest-dir>` creates a timestamped subdirectory under the given
destination containing:

| File | Content |
| ---- | ------- |
| `parttable.txt` | exact partition table (`sfdisk -d`) |
| `<part>.ntfsclone.zst` | NTFS partition, used clusters only (`ntfsclone` + zstd) |
| `<part>.raw.zst` | ESP/MSR and any other partitions (`dd` + zstd) |
| `restore-notes.txt` | ready-to-run restore commands |

Requirements: the VM must be closed and the SSD's partitions unmounted (the
script enforces both). Imaging reads the disk while it is idle — a fresh
installation images in roughly 20–30 GB instead of the disk's full 954 GB.

Restore (the commands are also written into `restore-notes.txt`, using a
`/dev/sdX` placeholder because the disk may enumerate under a different name
at restore time):

```sh
# 1. Plug in the SSD; check its current name — it may differ from the one it
#    had when imaged (lsblk). Adjust /dev/sdX below if needed.
#    Repartition exactly:
sudo sfdisk /dev/sdX < parttable.txt
# 2. Restore each partition, in order (from restore-notes.txt). Partition
#    numbers are preserved 1:1 by the saved table; only the sdX prefix can
#    change:
zstd -dc sda1.raw.zst | sudo dd of=/dev/sdX1 bs=4M status=progress
zstd -dc sda3.ntfsclone.zst | sudo ntfsclone -r -o /dev/sdX3 -
```

Then boot with `win-usb` (or F9 on real hardware). Restoring a snapshot is
destructive — it overwrites whatever is currently on the SSD.

Tip: image the disk while the Windows installation is still pristine (before
installing lots of software). If you want the restored system to skip the
OOBE, either keep the post-install state (as imaged) or run `sysprep` inside
Windows before imaging.

## Limitations and caveats

- **No GPU acceleration in the VM** — Windows uses the Microsoft Basic
  Display Adapter. Use the real-hardware boot (F9) for GPU work.
- **Keep BitLocker off** — a portable USB system should not be locked to one
  machine's TPM.
- **One VM (or imager) at a time** — flock-based exclusivity: only one of
  `win-usb`/`win-usb-image` may touch the disk at once.
- **Drivers** — NVIDIA (RTX 4000 Ada) and other vendor drivers are installed
  inside Windows after first boot; they are not part of the NixOS config.
- **The VM is not a backup** — `win-usb-image` snapshots are; store them on
  the NAS (`win-usb-image /mnt/nas/win2go-images`) and treat a restore drill
  like the other manual-verification items in `docs/testing.md`.

## Troubleshooting

- **"expected exactly one KIOXIA USB SSD, found N"** — with 0, the SSD is
  unplugged or the model matcher in `modules/nixos/win2go.nix` no longer
  matches (new enclosure/SSD); with more than 1, several KIOXIA USB disks are
  attached — unplug the others (the scripts refuse to guess).
- **"a VM already has $dev attached"** — close the other VM window, or
  `sudo pkill -f qemu-system-x86_64` if it is stuck.
- **"another win-usb/win-usb-image is already using $dev"** — the disk's
  `flock` is held by another invocation; wait for it to finish (or close the
  other VM).
- **VM boots into Setup instead of Windows** — stale or missing NVRAM:
  delete `~/.local/share/win2go/OVMF_VARS.fd` and retry.
- **Windows is slow in the VM** — expected: no GPU acceleration and the USB
  link is the bottleneck. Boot on real hardware for demanding workloads.
