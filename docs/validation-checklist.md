# Validation Checklist

Run after first install and after significant updates. Each check has the exact command and expected result.

## M1 — Bootable appliance

- [ ] **Host builds from flake**
  ```sh
  nix flake check
  ```
  Expected: no errors.

- [ ] **`enp1s0` comes up (dwmac_motorcomm driver)**
  ```sh
  ip link show enp1s0
  ```
  Expected: state `UP`, driver `dwmac_motorcomm` (check with `ethtool -i enp1s0`).

- [ ] **Static LAN IP reachable**
  ```sh
  ping -c 3 10.0.0.9
  ```
  Expected: replies from Soyo.

- [ ] **SSH by IP works**
  ```sh
  ssh krzysiek@10.0.0.9 hostname
  ```
  Expected: key-only auth, outputs `soyo`. Root SSH should be refused.

- [ ] **`soyo.home.arpa` resolves**
  ```sh
  dig +short soyo.home.arpa @10.0.0.9
  ```
  Expected: `10.0.0.9`.

- [ ] **Bare `soyo` resolves (search domain)**
  ```sh
  ping -c 1 soyo
  ```
  Expected: resolves to `10.0.0.9`.

- [ ] **DHCP leases handed out**
  Disconnect and reconnect a LAN client (or renew lease: `sudo dhclient -r && sudo dhclient`). Check:
  ```sh
  cat /var/lib/dnsmasq/dnsmasq.leases
  ```
  Expected: entries with client IPs and lease times.

- [ ] **Clients receive correct DHCP options**
  On a DHCP client:
  ```sh
  cat /etc/resolv.conf
  ```
  Expected: nameserver `10.0.0.9`, search `home.arpa`.

- [ ] **Blocky answers from upstream**
  ```sh
  dig +short example.com @10.0.0.9
  ```
  Expected: resolves (not blocked or NXDOMAIN).

- [ ] **Ad/tracker blocking works**
  ```sh
  dig +short doubleclick.net @10.0.0.9
  ```
  Expected: `0.0.0.0` (Blocky zeroIP block).

- [ ] **Local reverse lookup works**
  ```sh
  dig +short -x 10.0.0.9 @10.0.0.9
  ```
  Expected: `soyo.home.arpa` or hostname.

- [ ] **Impermanent root: state survives reboot**
  ```sh
  # Before reboot: check a persisted path
  ls /persist/etc/ssh/ssh_host_ed25519_key

  # After reboot: verify it's still there AND agenix succeeded
  ssh krzysiek@10.0.0.9 hostname
  ```
  Expected: SSH key stable, SSH login still works.

- [ ] **TPM auto-unlock succeeds on reboot**
  ```sh
  sudo systemctl reboot
  # Wait ~60 seconds, then:
  ssh krzysiek@10.0.0.9 hostname
  ```
  Expected: reaches stage-2 without passphrase. If this fails, use break-glass and re-enroll TPM.

- [ ] **Break-glass passphrase unlock works**
  ```sh
  # Temporarily wipe the TPM keyslot
  sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
  sudo systemctl reboot
  # Unlock with passphrase (console or initrd SSH)
  # After boot, re-enroll:
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/luks
  ```
  Expected: passphrase unlocks the disk.

- [ ] **LAN initrd SSH unlock**
  ```sh
  ssh -p 2222 root@10.0.0.9
  ```
  Expected: initrd SSH prompt (enter passphrase). Only works when system is at the initrd unlock stage.

- [ ] **Direct-link rescue unlock**
  1. Connect laptop directly to Soyo's Ethernet port.
  2. `sudo ip addr add 192.168.254.1/30 dev eth0 && sudo ip link set eth0 up`
  3. `ssh -p 2222 root@192.168.254.2`
  Expected: initrd SSH prompt over the direct link.

## M2 — Durability & operations

- [ ] **agenix secrets decrypt on host**
  ```sh
  sudo ls /run/agenix/
  ```
  Expected: `root-password`, `krzysiek-password`, `restic-password`, `ntfy-token`.

- [ ] **nix.gc configured**
  ```sh
  systemctl list-timers nix-gc
  ```
  Expected: `nix-gc.timer` exists, weekly.

- [ ] **Btrfs scrub scheduled**
  ```sh
  systemctl list-timers btrfs-scrub
  ```
  Expected: `btrfs-scrub.timer` exists, monthly.

- [ ] **SMART monitoring active**
  ```sh
  sudo smartctl -a /dev/disk/by-id/ata-PELADN_512GB_20250522100164 | grep "Self-test"
  ```
  Expected: shows scheduled short (daily 02:00) and long (Sunday 03:00) tests.

- [ ] **Journald bounded**
  ```sh
  journalctl --header | grep "System Max Use"
  ```
  Expected: `500.0M`.

- [ ] **Forced unit failure sends ntfy**
  ```sh
  # Create a failing one-shot unit
  sudo systemd-run --unit test-ntfy-onfailure sh -c 'exit 1'
  # Wait a few seconds, check ntfy.sh/soyo-alerts for "soyo unit failed: test-ntfy-onfailure"
  sudo systemctl reset-failed
  ```
  Expected: ntfy notification received.

- [ ] **Free-space check active**
  ```sh
  systemctl list-timers free-space-check
  ```
  Expected: `free-space-check.timer` exists, hourly.

- [ ] **Low free-space alert**
  Fill the disk to trigger (or temporarily set threshold to `0` and redeploy). Expected: ntfy notification "soyo low disk space".

- [ ] **btrbk snapshots created**
  ```sh
  sudo btrbk -c /etc/btrbk/soyo.conf list
  ```
  Expected: snapshots listed under `/snapshots/persist/` and `/snapshots/root/`.

- [ ] **restic backup runs**
  ```sh
  sudo systemctl start restic-backups-soyo
  sudo journalctl -u restic-backups-soyo -f
  ```
  Expected: snapshot created on the Synology.

- [ ] **restic restore drill**
  ```sh
  sudo restic -r sftp:soyo-backup@nas.home.arpa:/backup/soyo \
    -p /run/agenix/restic-password restore latest --target /tmp/restic-test \
    --include /persist/var/lib/dnsmasq
  diff -r /tmp/restic-test/persist/var/lib/dnsmasq /var/lib/dnsmasq
  sudo rm -rf /tmp/restic-test
  ```
  Expected: content identical.

- [ ] **node_exporter metrics available**
  ```sh
  curl -s 10.0.0.9:9100/metrics | head
  ```
  Expected: Prometheus metrics output.

- [ ] **dnsmasq exporter metrics available**
  ```sh
  curl -s 10.0.0.9:9153/metrics | head
  ```
  Expected: Prometheus metrics output (DHCP lease count, DNS query stats).

- [ ] **Synology Uptime Kuma probe**
  On the Synology: add a DNS monitor in Uptime Kuma querying `10.0.0.9:53` for `soyo.home.arpa`. Power off Soyo. Expected: probe reports DNS down.

- [ ] **Rollback documented and tested**
  Follow `docs/update-and-rollback.md`. Expected: previous generation boots.

- [ ] **Native `nixos-rebuild --target-host` works**
  ```sh
  ./scripts/deploy-soyo
  ```
  Expected: builds locally, activates on Soyo.

## M3 — Security hardening (Phase 2, future)

- [ ] **Secure Boot enabled**
  ```sh
  sudo sbctl status
  ```
  Expected: "Setup Mode: User", "Secure Boot: enabled", files signed.

- [ ] **Limine secureBoot enabled**
  Check `boot.loader.limine.secureBoot.enable = true` in `hosts/soyo/boot.nix`. Expected: build succeeds (module force-enables enrollConfig, validateChecksums, panicOnChecksumMismatch).

- [ ] **Tampered cmdline/kernel fails to boot**
  Edit the boot entry cmdline or replace the kernel image. Expected: boot fails (checksum mismatch or enrolled config violation).

- [ ] **TPM auto-unlock survives kernel update**
  Update nixpkgs, deploy (new kernel). Reboot. Expected: still auto-unlocks (PCR 0+2+7 stable across kernel/initrd updates).

- [ ] **TPM re-enrollment restores auto-unlock after deliberate PCR change**
  ```sh
  sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks
  sudo systemctl reboot
  ```
  Expected: auto-unlocks again.
