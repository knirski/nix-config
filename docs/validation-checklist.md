# Validation Checklist

Run after first install and after significant updates. Each check has the exact
command and expected result.

> **Hostname vs IP:** Most commands use `soyo` (resolved via Blocky from
> `reservations.nix`). If DNS isn't working yet, fall back to the static IP
> `10.0.0.9` (e.g. `ssh krzysiek@10.0.0.9`, `dig @10.0.0.9`).

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
  ping -c 3 soyo
  ```
  Expected: replies from Soyo.

- [ ] **SSH by IP works**
  ```sh
  ssh krzysiek@soyo hostname
  ```
  Expected: key-only auth, outputs `soyo`. Root SSH should be refused.

- [ ] **`soyo.home.arpa` resolves**
  ```sh
  dig +short soyo.home.arpa @soyo
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
  dig +short example.com @soyo
  ```
  Expected: resolves (not blocked or NXDOMAIN).

- [ ] **Ad/tracker blocking works**
  ```sh
  dig +short doubleclick.net @soyo
  ```
  Expected: `0.0.0.0` (Blocky zeroIP block).

- [ ] **Local reverse lookup works**
  ```sh
  dig +short -x 10.0.0.9 @soyo
  ```
  Expected: `soyo.home.arpa` or hostname.

- [ ] **Impermanent root: state survives reboot**
  ```sh
  # Before reboot: check a persisted path
  ls /persist/etc/ssh/ssh_host_ed25519_key

  # After reboot: verify it's still there AND agenix succeeded
  ssh krzysiek@soyo hostname
  ```
  Expected: SSH key stable, SSH login still works.

- [ ] **TPM auto-unlock succeeds on reboot**
  ```sh
  sudo systemctl reboot
  # Wait ~60 seconds, then:
  ssh krzysiek@soyo hostname
  ```
  Expected: reaches stage-2 without passphrase. If this fails, use break-glass and re-enroll TPM.

- [ ] **Break-glass passphrase unlock works**
  ```sh
  # Temporarily wipe the TPM keyslot
  sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
  sudo systemctl reboot
  # Unlock with passphrase (console or initrd SSH)
  # After boot, re-enroll:
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks
  ```
  Expected: passphrase unlocks the disk.

- [ ] **LAN initrd SSH unlock**
  ```sh
  ssh -p 2222 root@soyo
  # If you land at -bash-5.3#, run:
  systemd-tty-ask-password-agent --watch
  ```
  Expected: initrd SSH shell or prompt, then the LUKS passphrase prompt. Only works when system is at the initrd unlock stage.

- [ ] **Direct-link rescue unlock**
  1. Connect laptop directly to Soyo's Ethernet port.
  2. `sudo ip addr add 192.168.254.1/30 dev eth0 && sudo ip link set eth0 up`
  3. `ssh -p 2222 root@192.168.254.2`
  4. If you land at `-bash-5.3#`, run `systemd-tty-ask-password-agent --watch`.
  Expected: initrd SSH shell or prompt over the direct link, then the LUKS passphrase prompt.

## M2 — Durability & operations

- [ ] **agenix secrets decrypt on host**
  ```sh
  sudo ls /run/agenix/
  ```
  Expected: `root-password`, `krzysiek-password`, `restic-password`,
  `ntfy-token`, `ntfy-topic`, `grafana-admin-password`, `tailscale-auth-key`.

- [ ] **CI pipeline passes on push**
  ```sh
  # Check https://github.com/knirski/nix-config/actions
  ```
  Expected: the most recent push shows a green checkmark for the `CI` workflow.

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
  curl -s soyo:9100/metrics | head
  ```
  Expected: Prometheus metrics output.

- [ ] **dnsmasq exporter metrics available**
  ```sh
  curl -s soyo:9153/metrics | head
  ```
  Expected: Prometheus metrics output (DHCP lease count, DNS query stats).

- [ ] **Grafana dashboard reachable**
  ```sh
  curl -so /dev/null -w '%{http_code}' http://soyo:3000
  ```
  Expected: `200` or `302` (Grafana redirects to login). Prometheus datasource should be pre-provisioned.

- [ ] **Grafana alert rules provisioned**
  ```sh
  curl -s -u admin:"$(sudo cat /run/agenix/grafana-admin-password)" \
    http://127.0.0.1:3000/api/v1/provisioning/alert-rules \
    | jq '.[].title'
  ```
  Expected: four rule titles — "Disk space low on /persist", "Backup failed",
  "Service down: Blocky DNS", "Service down: dnsmasq". All have `for: 5m`
  (tolerates `nixos-rebuild` service restarts without false alerts).

- [ ] **Tailscale connected**
  ```sh
  ssh krzysiek@soyo tailscale status
  ```
  Expected: shows "soyo" as connected with a Tailscale IP. The auth key auto-authenticates on first boot.

- [ ] **Synology Uptime Kuma probe**
  On the Synology: add a DNS monitor in Uptime Kuma querying `soyo:53` for `soyo.home.arpa`. Power off Soyo. Expected: probe reports DNS down.

- [ ] **Rollback documented and tested**
  Follow `docs/update-and-rollback.md`. Expected: previous generation boots.

- [ ] **Native `nixos-rebuild --target-host` works**
  ```sh
  ./scripts/deploy-soyo.sh
  ```
  Expected: builds locally, activates on Soyo.

## M3 — Security hardening

- [ ] **Secure Boot enabled**
  ```sh
  sudo sbctl status
  sudo sbctl list-enrolled-keys
  ```
  Expected: `Setup Mode: User`, `Secure Boot: enabled`, and enrolled `PK`, `KEK`, and `db` keys. `Installed:` may still be false because the NixOS Limine module signs the EFI binary directly instead of registering it in sbctl's file database.

- [ ] **sbctl key state persisted**
  ```sh
  sudo ls /persist/var/lib/sbctl/keys
  ```
  Expected: the PK/KEK/db key hierarchy exists under `/persist/var/lib/sbctl/keys`. Without this durable copy, future Limine updates cannot be signed after a reboot.

- [ ] **Limine secureBoot enabled**
  Check `boot.loader.limine.secureBoot.enable = true` in `hosts/soyo/boot.nix`. Expected: build succeeds (module force-enables enrollConfig, validateChecksums, panicOnChecksumMismatch).

- [ ] **Tampered cmdline/kernel fails to boot**
  Edit the boot entry cmdline or replace the kernel image. Expected: boot fails (checksum mismatch or enrolled config violation).

- [ ] **Deploy still works with Secure Boot enabled**
  ```sh
  ./scripts/deploy-soyo.sh
  ```
  Expected: activation succeeds. In particular, the bootloader step does not fail with `There are no sbctl secure boot keys present. Please generate some.`

- [ ] **TPM auto-unlock survives kernel update**
  Update nixpkgs, deploy (new kernel). Reboot. Expected: still auto-unlocks (PCR 0+2+7 stable across kernel/initrd updates).

- [ ] **TPM re-enrollment restores auto-unlock after deliberate PCR change**
  ```sh
  sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks
  sudo systemctl reboot
  ```
  Expected: auto-unlocks again.
