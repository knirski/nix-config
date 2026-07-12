# Secrets in nix-config

This repo uses **agenix** + **agenix-rekey** to manage secrets like passwords
and API tokens.  When you deploy to a host, the secret files land on the target
machine already encrypted, and only that machine's SSH host key can decrypt
them at boot time — so even if your git repo is public, the secrets stay safe.

If you are new to encrypted secrets this walkthrough explains the ideas first,
then the concrete file layout and daily commands.

---

## Table of Contents

- [What is a secret?](#what-is-a-secret)
- [How encryption works: asymmetric keys](#how-encryption-works-asymmetric-keys)
- [Two key roles: master key and host key](#two-key-roles-master-key-and-host-key)
- [The two-layer rekeyFile flow](#the-two-layer-rekeyfile-flow)
- [File layout in this repo](#file-layout-in-this-repo)
- [Bootstrap: first install without a known host key](#bootstrap-first-install-without-a-known-host-key)
- [Daily operations](#daily-operations)
  - [Edit a secret (change a password)](#edit-a-secret-change-a-password)

  - [Add a new secret](#add-a-new-secret)

  - [Add a new host](#add-a-new-host)

- [Key rotation & recovery](#key-rotation--recovery)
  - [Change a secret on a running system](#change-a-secret-on-a-running-system)

  - [Rotate the master key](#rotate-the-master-key)

  - [Rotate a host key](#rotate-a-host-key)

- [Reference: key files and where they live](#reference-key-files-and-where-they-live)

---

## What is a secret?

A **secret** is any value you do not want to commit in plain text:
user password hashes, API tokens for backup services, database passwords.
In this repo secrets are:

- **Hashed passwords** — `mkpasswd -m sha-512` output (never the raw password)
- **Restic repo password** — the passphrase for the backup repository
- **ntfy authentication token** — for push notification alerts

**MAC and IP addresses are NOT secrets** — they appear in plaintext in the
repo (e.g. `hosts/soyo/reservations.nix`).

---

## How encryption works: asymmetric keys

The tool we use is **rage** (a Rust implementation of the `age` file encryption
format).  age uses **asymmetric (public-key) cryptography**:

- A **public key** can encrypt a file, but cannot decrypt it.
- A **private key** decrypts files that were encrypted with the matching
  public key.

You share your public key freely; you guard your private key with your life.

```text
                    public key                    private key
                       │                              │
   "hello" ──► encrypt ──► encrypted file ──► decrypt ──► "hello"
```

### SSH keys are already age keys

If you already have an SSH key (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`), you
already have an age-compatible keypair.  The tool **ssh-to-age** converts
an SSH public key into an age public key:

```bash
ssh-to-age < ~/.ssh/id_ed25519.pub
# age1abc123def...
```

The private key stays the same SSH key — rage can decrypt with it directly.
No extra key to manage.

---

## Two key roles: master key and host key

This repo uses separate keypairs for separate jobs. The names can be confusing,
so keep this rule in mind:

> A key under the operator's `~/.ssh/` is an operator/client key. A key under
> `/persist/etc/ssh/` is a machine's host key. They must not be swapped.

### Master identity (your SSH key)

- **Who holds it:** the operator (you).
- **What it does:** lets you edit and rekey secrets.
- **Where agenix-rekey finds it:** `/etc/agenix-rekey/master-identity` on the
  operator machine. This is a symlink to the real SSH private key, which may
  live anywhere outside the repository and Nix store.
- **Its public key in the repo:** `secrets/krzysiek.age.pub`.

Every master-encrypted `.age` file in `secrets/` can be decrypted only by
someone holding the matching SSH private key.  This is how we keep secrets
editable by the right people while still committing them to git.

Both host assemblers use the same stable operator-side path. Set it up on each
operator environment from which you run `agenix edit` or `agenix rekey`. The
symlink target is local to that environment; it is not a host key and does not
need to exist on every machine.

```bash
sudo install -d -m 755 /etc/agenix-rekey
sudo ln -sfn "$HOME/.ssh/soyo_ed25519" /etc/agenix-rekey/master-identity
```

The current operator key is named `soyo_ed25519`, but that filename is only a
local convention. Point the symlink at whichever private key matches
`secrets/krzysiek.age.pub`; verify the public half before rekeying:

```bash
ssh-keygen -y -f "$HOME/.ssh/soyo_ed25519" > /tmp/master.pub
diff -u <(awk '{print $1" "$2}' "$HOME/.ssh/soyo_ed25519.pub") \
  <(awk '{print $1" "$2}' /tmp/master.pub)
rm -f /tmp/master.pub
```

The assembler stores the `/etc` path as an
**absolute string**, not a Nix path literal. Therefore evaluation does not
require the key to exist and Nix does not copy it into the world-readable
store. `agenix edit`, `agenix rekey`, and `agenix generate` require the symlink
target at runtime. Do not use `builtins.getEnv` or put the private key in this
repository: the former makes evaluation impure, while the latter can expose the
key through the store.

### Host key (the machine's SSH host key)

- **Who holds it:** the target machine (e.g. Soyo).
- **What it does:** lets that machine decrypt secrets at boot time.
- **Where it lives:** `/persist/etc/ssh/ssh_host_ed25519_key` on the target.
- **Its public key in the repo:** `secrets/<host>.pub` (for example,
  `secrets/soyo.pub` or `secrets/zbook.pub`).

Each host has its own SSH host key, so a compromised machine cannot decrypt
secrets meant for a different machine.

### Why must they be different keys?

It would be *convenient* to use your personal SSH key as both the master
identity and Soyo's host key — one keypair to rule them all.  **Do not do
this.**  Here is why:

- **Different trust boundaries.** Your personal key proves *you* are who you
  say you are.  Soyo's host key proves *Soyo* is who it says it is.  These
  are different claims.  If they are the same key, there is no way to
  distinguish "Krzysztof is SSHing into the build server" from "Soyo is
  decrypting secrets at boot" — they both use the same credential.

- **Blast radius.** If you copy your personal private key onto Soyo so it
  can decrypt secrets, a compromised Soyo gives an attacker your personal
  key.  Now they can:

  - SSH into every other machine as you.

  - Sign commits and git operations as you.

  - Decrypt every secret in the repo (master files + any host's rekeyed
    files).

  - Re-encrypt secrets for their own keys and push them to the repo.

  With separate keys, a compromised Soyo only gives the attacker Soyo's
  host key — they can decrypt secrets meant for Soyo, but nothing else.
  Your personal key never leaves your workstation.

- **Rotation independence.** If you rotate your personal SSH key (moved to
  a new laptop, YubiKey replaced, suspected compromise), you do not want
  to also break Soyo's ability to boot.  Separate keys let you rotate
  each one independently: update `krzysiek.age.pub`, rekey, deploy — Soyo
  keeps its own key and keeps running.

- **Multi-host scalability.** With N hosts, using your personal key as every
  host's key means either (a) every host gets a copy of your private key
  (disaster), or (b) you generate N keypairs anyway and enroll each one as a
  recipient in `secrets.nix` — which is exactly what the two-layer rekeyFile
  flow does automatically.

**In short:** The master identity is *you*; a host key is *that machine*.
They are different actors with different privileges.  Keeping them separate
is the entire point of the rekeyFile design.

---

## The two-layer rekeyFile flow

Instead of encrypting every secret for every machine directly (which would
mean re-encrypting *N* secrets × *M* hosts every time a password changes),
we use a two-layer approach:

```text
Layer 1 (in git)                    Layer 2 (in git)
┌─────────────────┐    agenix rekey   ┌──────────────────────┐
│ secrets/        │ ─────────────────►│ secrets/rekeyed/     │
│ root-password   │   decrypt with    │   soyo/              │
│    .age         │   MASTER key      │   root-password      │
│                 │   re-encrypt with │      .age            │
│ (encrypted with │   HOST key        │                      │
│  krzysiek's     │                   │ (encrypted with      │
│  public key)    │                   │  soyo's public key)  │
└─────────────────┘                   └──────────────────────┘
                                            │
                                   nix build │
                                            ▼
                                     ┌──────────────┐
                                     │ Target       │
                                     │ machine      │
                                     │ decrypts     │
                                     │ with its     │
                                     │ SSH key      │
                                     └──────────────┘
```

**Step by step:**

1. You create or edit a secret and encrypt it with your **master identity**
   (your SSH key).  The result goes in `secrets/<name>.age`.

2. You run `agenix rekey`.  This app:
   - Decrypts each `.age` file using your SSH private key (you are the master).

   - Re-encrypts the plaintext with each **host's public key**.

   - Writes the host-specific files to `secrets/rekeyed/<host>/`.

3. You commit both layers to git.
4. When `nixos-rebuild` runs on the target, agenix's activation script
   decrypts the rekeyed files using the target's **SSH host private key**
   and places the plaintext at the paths your config expects (e.g.
   `/run/agenix/root-password`).

### Why two layers?

- **One source of truth.**  Edit one master file, rekey, and every host gets
  the update — no per-host editing.

- **Host isolation.**  A compromised host's SSH key can only decrypt its own
  rekeyed files, not the master files or another host's files.

- **Git-safe.**  Both layers are encrypted; public repo is fine.

---

## File layout in this repo

```text
secrets/
├── krzysiek.age.pub        # Master identity public key (plaintext)
├── krzysiek-authorized-key.pub  # krzysiek's SSH authorized key (plaintext)
├── soyo.pub                # Soyo host SSH public key (plaintext; enrolled
│                           #   during first install)
├── zbook.pub               # zbook host SSH public key (plaintext)
├── root-password.age       # Master-encrypted (krzysiek's key)
├── krzysiek-password.age   # Master-encrypted
├── soyo-restic-password.age  # Master-encrypted (Soyo restic repo)
├── zbook-restic-password.age # Master-encrypted (zbook restic repo)
├── ntfy-token.age          # Master-encrypted (ntfy.sh access token)
├── ntfy-topic.age          # Master-encrypted (ntfy.sh topic URL)
├── grafana-admin-password.age # Master-encrypted (Grafana admin password)
├── grafana-secret-key.age     # Master-encrypted (Grafana session signing key)
├── tailscale-auth-key-soyo.age  # Master-encrypted (Tailscale pre-auth key for soyo)
├── tailscale-auth-key-zbook.age # Master-encrypted (Tailscale pre-auth key for zbook)
└── rekeyed/
    └── soyo/               # Host-specific rekeyed files (soyo's key)
        ├── root-password.age
        ├── krzysiek-password.age
        ├── soyo-restic-password.age
        ├── ntfy-token.age
        ├── ntfy-topic.age
        ├── grafana-admin-password.age
        ├── grafana-secret-key.age
        └── tailscale-auth-key-soyo.age  # (rekeyed for soyo; zbook's in rekeyed/zbook/)
```

Files under `secrets/rekeyed/` are produced by `agenix rekey` and tracked in
git. Their hash-prefixed names are generated by agenix-rekey and are not
hand-maintained names; the source `rekeyFile` and host directory identify what
they contain. They contain the same plaintext as the master files but are
encrypted for a specific host's SSH key instead of your master key.

### What each file is

| File | Contains | Encrypted for |
| ---- | -------- | -------------- |
| `secrets/root-password.age` | root's SHA-512 password hash | master identity |
| `secrets/krzysiek-password.age` | krzysiek's SHA-512 password hash | master identity |
| `secrets/soyo-restic-password.age` | Soyo restic repo passphrase | master identity |
| `secrets/zbook-restic-password.age` | zbook restic repo passphrase | master identity |
| `secrets/ntfy-token.age` | ntfy.sh access token | master identity |
| `secrets/ntfy-topic.age` | ntfy.sh topic URL | master identity |
| `secrets/grafana-admin-password.age` | Grafana admin password | master identity |
| `secrets/grafana-secret-key.age` | Grafana session signing key | master identity |
| `secrets/tailscale-auth-key-soyo.age` | Tailscale pre-auth key for soyo | master identity |
| `secrets/tailscale-auth-key-zbook.age` | Tailscale pre-auth key for zbook | master identity |
| `secrets/krzysiek.age.pub` | Master/operator public key (plaintext) | n/a — recipient metadata for the master identity |
| `secrets/krzysiek-authorized-key.pub` | Operator public key (plaintext) | n/a — consumed by SSH authorized keys and initrd unlock |
| `secrets/soyo.pub` | Soyo's raw SSH host public key (plaintext) | n/a — recipient metadata for Soyo rekeying |
| `secrets/zbook.pub` | ZBook's raw SSH host public key (plaintext) | n/a — recipient metadata for ZBook rekeying |
| `secrets/rekeyed/soyo/...` | same content as above | Soyo's SSH host key |
| `secrets/rekeyed/zbook/...` | same content as above | ZBook's SSH host key |

---

## Bootstrap: first install without a known host key

There is a chicken-and-egg problem: we need the target's SSH host key to
rekey secrets for it, but the host key is generated during first install.
And we need rekeyed secrets before `nixos-install` runs.

**The install procedure solves this by generating the host key on the live
ISO, before installation.**  The rough order:

1. Boot the NixOS live ISO on the target.
2. Clone this repo and generate the SSH host key into `/mnt/persist/etc/ssh/`:

   ```bash
   sudo install -d -m 700 /mnt/persist/etc/ssh
   sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
   ```

3. Overwrite `secrets/soyo.pub` with the real host public key:

   ```bash
   sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub > secrets/soyo.pub
   ```

4. Rekey all secrets for the new host key:

   ```bash
   nix develop '.#' -c agenix rekey
   ```

5. Commit the enrolled pubkey and rekeyed files:

   ```bash
   git add secrets/soyo.pub secrets/rekeyed/
   git commit -m "feat: enroll soyo agenix recipient and rekey secrets"
   ```

6. Run `nixos-install --flake .#soyo` — the rekeyed secrets are already in
   the repo, so they land on the target and are decrypted on first boot.

**Why an SSH public key and not an age X25519 key?**  The agenix activation
script on the target uses the Go `age` binary with `-i ssh_key` to decrypt
rekeyed secrets.  Go `age` converts SSH ed25519 → X25519 internally when
given an `-> ssh-ed25519` recipient, but it *cannot* match an SSH private
key to an `-> X25519` recipient.  Therefore `hostPubkey` must point to the
raw SSH public key so rekeyed files use `-> ssh-ed25519` recipients.

**Why generate the host key before `nixos-install`?**  The normal pattern
for agenix-rekey is to deploy with a dummy placeholder, then overwrite
it after first boot.  Generating the key on the live ISO avoids this dance:
the host key is real from the start, the rekeyed secrets are real, and the
first boot decrypts them without a manual password-copying step.

See [`docs/install-soyo.md`](install-soyo.md) for the full concrete steps.

---

## Daily operations

### Edit a secret (change a password)

```bash
# 1. Generate a new SHA-512 password hash
mkpasswd -m sha-512

# 2. Edit the master-encrypted secret
#    agenix edit decrypts with your SSH key, opens $EDITOR, re-encrypts
nix develop '.#' -c agenix edit secrets/root-password.age

# 3. Rekey so the change propagates to host-specific rekeyed files
nix develop '.#' -c agenix rekey

# 4. Commit and deploy
git add secrets/root-password.age secrets/rekeyed/
git commit -m "chore: update root password"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

### Add a new secret

1. Choose a name, e.g. `my-api-token`.
2. Create the encrypted file:

   ```bash
   # Encrypt the secret with your master key
   echo -n "my-api-token-value" | nix develop '.#' -c agenix edit secrets/my-api-token.age
   ```

   Or pipe content directly:

   ```bash
   echo -n "my-api-token-value" \
     | nix run nixpkgs#rage -- -e -i /etc/agenix-rekey/master-identity \
       -o secrets/my-api-token.age
   ```

3. In `modules/nixos/users.nix` (or the appropriate module), add:

   ```nix
   age.secrets.my-api-token.rekeyFile = ../../secrets/my-api-token.age;
   ```

4. Rekey and commit:

   ```bash
   nix develop '.#' -c agenix rekey
   git add secrets/my-api-token.age secrets/rekeyed/
   git commit -m "feat: add my-api-token secret"
   ```

5. Reference the decrypted secret in your NixOS config:

   ```nix
   services.some-service.environmentFile = config.age.secrets.my-api-token.path;
   ```

### Add a new host

1. Create the host directory and assembler module (see AGENTS.md "Adding a host").
2. Include the `users` aspect to reuse the secret inventory.
3. In the host assembler, set `age.rekey.hostPubkey = ../../secrets/<host>.pub;`.
4. On the target machine (or live ISO), generate an SSH host key:

   ```bash
   sudo install -d -m 700 /mnt/persist/etc/ssh
   sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
   ```

5. Copy the public key into the repo:

   ```bash
   sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub > secrets/<host>.pub
   ```

6. Run `agenix rekey` — it will rekey all secrets for the new host.
7. Deploy.

   If the host key can't be generated before the first build (e.g. you're
   provisioning remotely), seed `secrets/<host>.pub` with a dummy SSH public
   key to satisfy the build, then follow steps 4–6 after the host is running.

---

## Key rotation & recovery

### Safe operator commands

Two destructive workflows are packaged as reviewed flake apps. Always preview
them first:

```bash
nix run .#set-tailscale-keys -- \
  --soyo-key-file /run/user/$UID/soyo.key \
  --zbook-key-file /run/user/$UID/zbook.key \
  --dry-run

nix run .#recover-secrets -- --revision 061eb80 --host zbook --dry-run
```

The key files should be mode `0600` on a temporary, user-private filesystem.
Secret values are never accepted as command-line arguments because argv can be
visible to other local processes and may be retained in shell history. A real
run additionally requires `--yes`; both commands use a private temporary
directory, clean it on exit, and stage destination files before replacement.

`set-tailscale-keys` runs `agenix rekey` after replacing both master-encrypted
files. `recover-secrets` deliberately does not rekey. Neither command stages,
commits, pushes, deploys, or prints plaintext. After either command, inspect
`git diff`, run the documented checks, and commit the encrypted outputs
manually. If rekeying fails, inspect `secrets/rekeyed/` before retrying because
that upstream operation manages its own generated outputs.

### Change a secret on a running system

Use the same flow for any secret — password hash, API token, or backup passphrase:

```bash
# 1. Generate the new value
mkpasswd -m sha-512                  # for a password hash
echo -n "new-ntfy-token" > /dev/null # replace with your actual token

# 2. Re-encrypt the master file with your SSH key
echo -n "new-value" \
  | nix run nixpkgs#rage -- -e -i /etc/agenix-rekey/master-identity \
    -o secrets/ntfy-token.age

# 3. Rekey for all hosts
nix develop '.#' -c agenix rekey

# 4. Commit and deploy
git add secrets/ntfy-token.age secrets/rekeyed/
git commit -m "chore: update ntfy token"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

After deploy, the new value is live. No reboot needed.

### Rotate the master key

Reasons to rotate: your SSH key is compromised, you got a new laptop, you
want to use a YubiKey, or simply periodic key rotation policy.

Whatever the reason, every master-encrypted `.age` file in `secrets/` must
be re-encrypted with the new key, and all hosts rekeyed.

**On your workstation:**

```bash
# 1. Generate a new SSH key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new

# 2. Derive the new age pubkey
ssh-to-age < ~/.ssh/id_ed25519_new.pub > secrets/krzysiek.age.pub

# 3. Re-encrypt every master .age file with the new key
for f in secrets/*.age; do
  rage -d -i ~/.ssh/id_ed25519_old "$f" \
    | rage -e -i ~/.ssh/id_ed25519_new -o "$f.tmp" \
    && mv "$f.tmp" "$f"
done

# 4. Retarget the operator-side symlink; no Nix edit is needed
sudo ln -sfn "$HOME/.ssh/id_ed25519_new" /etc/agenix-rekey/master-identity

# 5. Rekey for all hosts
nix develop '.#' -c agenix rekey

# 6. Commit
git add secrets/
git commit -m "fix: rotate compromised master key"

# 7. Deploy to every host
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

**After deploy:**

- The old key can no longer decrypt new master files.
- Hosts continue working — their rekeyed files are unchanged (still encrypted
  with each host's own key).

- Update your SSH config, GitHub deploy keys, etc. to use the new key.
- Securely destroy the old private key.

### Rotate a host key

Reasons to rotate: the machine's host key is compromised, you are rebuilding
from scratch and want fresh keys, or routine key rotation.

A rotated host key means old rekeyed secrets are no longer decryptable —
regenerate them before deploying.

**On the target machine (or live ISO with /persist mounted):**

```bash
# 1. Generate a new SSH host key
sudo ssh-keygen -t ed25519 -f /persist/etc/ssh/ssh_host_ed25519_key -N ""
```

**On your workstation:**

```bash
# 2. Copy the new SSH public key into the repo
#    (scp from the machine, or paste manually)
scp krzysiek@soyo:/persist/etc/ssh/ssh_host_ed25519_key.pub secrets/soyo.pub

# 3. Rekey — decrypts with your master key, re-encrypts with the new host key
nix develop '.#' -c agenix rekey

# 4. Commit and deploy
git add secrets/soyo.pub secrets/rekeyed/
git commit -m "fix: rotate compromised soyo host key"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

**After deploy:**

- The new host key is in use. Add it to your `known_hosts`:

  ```bash
  ssh-keygen -R soyo.home.arpa
  ssh krzysiek@soyo.home.arpa -o StrictHostKeyChecking=accept-new
  ```

- The old host key is replaced. If other machines had it in their
  `known_hosts`, they will warn on next SSH connection — verify and accept
  the new fingerprint.

- Secrets are now encrypted for the new key. The old key can no longer
  decrypt them.

---

## Reference: key files and where they live

The following is the current layout. ZBook is currently the main operator
machine, so its local `~/.ssh/soyo_ed25519` is the active master private key.
“Local operator machine” still means the machine where you run the rekey
command; if that changes, configure its local key and symlink accordingly.
The private keys are never stored in this repository.

| Keypair | Private key location | Public key location | Responsible for |
| --- | --- | --- | --- |
| Master/operator | Current main operator machine (ZBook): `~/.ssh/soyo_ed25519` | ZBook: `~/.ssh/soyo_ed25519.pub`; repo: `secrets/krzysiek.age.pub` | Decrypting master `.age` files and running `agenix rekey` |
| Operator SSH client for ZBook | Current main operator machine (ZBook): `~/.ssh/zbook_ed25519` | ZBook: `~/.ssh/zbook_ed25519.pub` | SSH client authentication, if selected for ZBook; not an agenix host key |
| Soyo host | Soyo only: `/persist/etc/ssh/ssh_host_ed25519_key` | Soyo: `/persist/etc/ssh/ssh_host_ed25519_key.pub`; repo: `secrets/soyo.pub` | Decrypting Soyo's rekeyed secrets at boot |
| ZBook host | ZBook only: `/persist/etc/ssh/ssh_host_ed25519_key` | ZBook: `/persist/etc/ssh/ssh_host_ed25519_key.pub`; repo: `secrets/zbook.pub` | Decrypting ZBook's rekeyed secrets at boot |

The operator private keys may be copied temporarily to a live environment when
that environment must run `agenix rekey` during installation. This is a
deliberate exception for bootstrap, not a reason to install the operator key
on the target permanently. At present, `~/.ssh/soyo_ed25519` does exist on
ZBook because ZBook is the main operator machine. Do not infer from that
current arrangement that the key must exist on a different workstation or on
a target host.

| File | Purpose | Created by |
| ---- | ------- | ----------- |
| `/etc/agenix-rekey/master-identity` | Operator-side symlink to the master **private** key | `ln -s` on each operator machine |
| `~/.ssh/soyo_ed25519` | Current local master/operator **private** key | `ssh-keygen` on the operator machine |
| `~/.ssh/soyo_ed25519.pub` | Current local master/operator public key | same |
| `~/.ssh/zbook_ed25519` | Local operator SSH **private** key for ZBook; not the ZBook host key | `ssh-keygen` on the operator machine |
| `~/.ssh/zbook_ed25519.pub` | Matching local operator SSH public key | same |
| `secrets/krzysiek.age.pub` | Master age public key, stored in repo | `ssh-to-age < ~/.ssh/soyo_ed25519.pub` (one-time setup) |
| `secrets/soyo.pub` | Soyo's SSH public key (raw, not age-converted) | `cat /persist/etc/ssh/ssh_host_ed25519_key.pub` during install |
| `/persist/etc/ssh/ssh_host_ed25519_key` | Soyo's SSH host **private** key | `ssh-keygen` during first install |
| `/persist/etc/ssh/ssh_host_ed25519_key.pub` | Soyo's SSH host public key | same |
| `secrets/*.age` | Master-encrypted secrets | `agenix edit ...` or `rage -e -i ...` |
| `secrets/rekeyed/<host>/*.age` | Host-specific rekeyed secrets | `agenix rekey` |

---

## Using `rage` with native SSH keys

`rage` (the Rust implementation of age) supports SSH private keys as native
identities — no conversion needed. The examples in this doc use `agenix edit`
for convenience, but you can work with `.age` files directly:

```bash
# Encrypt a file for the master identity
rage -e -r "$(ssh-to-age < ~/.ssh/soyo_ed25519.pub)" \
  < plaintext.txt > secrets/encrypted.age

# Decrypt with the SSH private key directly
rage -d -i /etc/agenix-rekey/master-identity secrets/encrypted.age
```

This only works when the file was encrypted for a recipient that matches the
SSH key (i.e. the age public key was derived from that SSH key via
`ssh-to-age`). The `agenix edit` command handles this correctly; raw `rage -e`
also works as long as you use `ssh-to-age` to derive the recipient.

The `masterIdentities` in both host assemblers point to the stable
`/etc/agenix-rekey/master-identity` symlink. `agenix rekey` passes its target to
`rage` as an identity, and `rage` handles the SSH private key directly.

---

## Further reading

- [age encryption format](https://age-encryption.org)
- [agenix](https://github.com/ryantm/agenix) — NixOS module for age secrets
- [agenix-rekey](https://github.com/oddlama/agenix-rekey) — rekeyFile flow
- [ssh-to-age](https://github.com/Mic92/ssh-to-age) — SSH → age key conversion
