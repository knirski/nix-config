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
  - [Rotate the master key (compromised operator key)](#rotate-the-master-key-compromised-operator-key)
  - [Rotate a host key (compromised machine)](#rotate-a-host-key-compromised-machine)
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

```
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

This repo uses **two separate keypairs** for two different jobs:

### Master identity (your SSH key)

- **Who holds it:** the operator (you).
- **What it does:** lets you edit and rekey secrets.
- **Where it lives:** `~/.ssh/id_ed25519` on your workstation.
- **Its public key in the repo:** `secrets/krzysiek.age.pub`.

Every master-encrypted `.age` file in `secrets/` can be decrypted only by
someone holding the matching SSH private key.  This is how we keep secrets
editable by the right people while still committing them to git.

### Host key (the machine's SSH host key)

- **Who holds it:** the target machine (e.g. Soyo).
- **What it does:** lets that machine decrypt secrets at boot time.
- **Where it lives:** `/persist/etc/ssh/ssh_host_ed25519_key` on the target.
- **Its public key in the repo:** `secrets/soyo.pub` (added during first install).

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

```
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

```
secrets/
├── krzysiek.age.pub        # Master identity public key (plaintext)
├── soyo.pub                # Soyo host SSH public key (plaintext; placeholder
│                           #   before first install)
├── root-password.age       # Master-encrypted (krzysiek's key)
├── krzysiek-password.age   # Master-encrypted
├── restic-password.age     # Master-encrypted
├── ntfy-token.age          # Master-encrypted
└── rekeyed/
    └── soyo/               # Host-specific rekeyed files (soyo's key)
        ├── root-password.age
        ├── krzysiek-password.age
        ├── restic-password.age
        └── ntfy-token.age
```

Files under `secrets/rekeyed/` are produced by `agenix rekey` and tracked in
git.  They contain the same plaintext as the master files but are encrypted
for a specific host's SSH key instead of your master key.

### What each file is

| File | Contains | Encrypted for |
|---|---|---|
| `secrets/root-password.age` | root's SHA-512 password hash | master identity |
| `secrets/krzysiek-password.age` | krzysiek's SHA-512 password hash | master identity |
| `secrets/restic-password.age` | Restic repo passphrase | master identity |
| `secrets/ntfy-token.age` | ntfy.sh access token | master identity |
| `secrets/rekeyed/soyo/...` | same content as above | Soyo's SSH host key |

---

## Bootstrap: first install without a known host key

There is a chicken-and-egg problem: we need Soyo's SSH host key to rekey
secrets for it, but Soyo generates its host key during the first install.
And we need the rekeyed secrets to build the system for that first install.

**agenix-rekey solves this with a dummy placeholder:**

The file at `age.rekey.hostPubkey` is pre-seeded with a well-known dummy
SSH public key for which **no one has the private key**.  When the system
sees this dummy key during `nix build`, it does not look for real rekeyed
files.  Instead it auto-generates **placeholder secrets** — dummy encrypted
files that satisfy the build but cannot actually be decrypted.

**Why an SSH public key and not an age X25519 key?**  The agenix activation
script on the target uses the Go `age` binary with `-i ssh_key` to decrypt
rekeyed secrets.  Go `age` converts SSH ed25519 → X25519 internally when
given an `-> ssh-ed25519` recipient, but it *cannot* match an SSH private
key to an `-> X25519` recipient.  Therefore `hostPubkey` must point to the
raw SSH public key so rekeyed files use `-> ssh-ed25519` recipients.

This allows:

1. Build and deploy the system (the placeholders get copied to the target).
2. During activation, decryption **fails** (expected — placeholder secrets
   cannot be decrypted by the real host key either).
3. A one-time manual step creates or copies the real password hashes onto
   the target, and the system boots without secrets.

Then:

4. Generate the SSH host key (first boot creates it on `/persist`).
5. Overwrite `secrets/soyo.pub` with the real SSH public key (the
   `hostPubkey` option already points to this file, so no config edit
   needed).
6. Run `agenix rekey` to produce real rekeyed files.
7. Redeploy — now the target can decrypt them.

> **Note:** The design doc's M1/M2 cut-line places the first install without
> rekeyed secrets; the full rekey workflow is completed as part of the
> deploy checklist.

See [`hosts/soyo/DEPLOY.md`](../hosts/soyo/DEPLOY.md) for the concrete steps.

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
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
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
     | nix run nixpkgs#rage -- -e -i ~/.ssh/id_ed25519 \
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
3. In the host assembler, set `age.rekey.hostPubkey = ../../secrets/<host>.pub;`
   and create a placeholder `secrets/<host>.pub` containing a dummy SSH public
   key (e.g. `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnownDummyKeyNoOneHasThePrivateKey=`).
   The dummy allows building before the real key exists.
4. On the target (or a one-time bootstrap key):
   - Generate an SSH host key.
   - Copy the SSH public key into the repo as `secrets/<host>.pub`.
5. Run `agenix rekey` — it will rekey all secrets for the new host.
6. Deploy.

---

## Key rotation & recovery

### Change a secret on a running system

Use the same flow for any secret — password hash, API token, or backup passphrase:

```bash
# 1. Generate the new value
mkpasswd -m sha-512                  # for a password hash
echo -n "new-ntfy-token" > /dev/null # replace with your actual token

# 2. Re-encrypt the master file with your SSH key
echo -n "new-value" \
  | nix run nixpkgs#rage -- -e -i ~/.ssh/id_ed25519 \
    -o secrets/ntfy-token.age

# 3. Rekey for all hosts
nix develop '.#' -c agenix rekey

# 4. Commit and deploy
git add secrets/ntfy-token.age secrets/rekeyed/
git commit -m "chore: update ntfy token"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

After deploy, the new value is live. No reboot needed.

### Rotate the master key (compromised operator key)

If your personal SSH key is compromised, all master-encrypted `.age` files
must be re-encrypted with a new key, and all hosts must be rekeyed.

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

# 4. Update masterIdentities in the host assembler to point to the new key
#    (absolute path on your workstation)
#    modules/parts/soyo.nix → masterIdentities = [ "/home/krzysiek/.ssh/id_ed25519_new" ];

# 5. Rekey for all hosts
nix develop '.#' -c agenix rekey

# 6. Commit
git add secrets/
git commit -m "fix: rotate compromised master key"

# 7. Deploy to every host
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

**After deploy:**
- The old key can no longer decrypt new master files.
- Hosts continue working — their rekeyed files are unchanged (still encrypted
  with each host's own key).
- Update your SSH config, GitHub deploy keys, etc. to use the new key.
- Securely destroy the old private key.

### Rotate a host key (compromised machine)

If a machine's SSH host key is compromised, that machine's rekeyed secrets
are exposed. Replace the host key and regenerate rekeyed files.

**On the compromised machine (or the live ISO with /persist mounted):**

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
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
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

| File | Purpose | Created by |
|---|---|---|
| `~/.ssh/id_ed25519` | Master **private** key (YOUR SSH key) | `ssh-keygen` on your workstation |
| `~/.ssh/id_ed25519.pub` | Master public key | same |
| `secrets/krzysiek.age.pub` | Master age public key, stored in repo | `ssh-to-age < ~/.ssh/id_ed25519.pub` (one-time setup) |
| `secrets/soyo.pub` | Soyo's SSH public key (raw, not age-converted) | `cat /persist/etc/ssh/ssh_host_ed25519_key.pub` during install |
| `/persist/etc/ssh/ssh_host_ed25519_key` | Soyo's SSH host **private** key | `ssh-keygen` during first install |
| `/persist/etc/ssh/ssh_host_ed25519_key.pub` | Soyo's SSH host public key | same |
| `secrets/*.age` | Master-encrypted secrets | `agenix edit ...` or `rage -e -i ...` |
| `secrets/rekeyed/<host>/*.age` | Host-specific rekeyed secrets | `agenix rekey` |

---

## Further reading

- [age encryption format](https://age-encryption.org)
- [agenix](https://github.com/ryantm/agenix) — NixOS module for age secrets
- [agenix-rekey](https://github.com/oddlama/agenix-rekey) — rekeyFile flow
- [ssh-to-age](https://github.com/Mic92/ssh-to-age) — SSH → age key conversion
