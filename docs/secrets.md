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
- **Its public key in the repo:** `secrets/soyo.age.pub` (added during first install).

Each host has its own SSH host key, so a compromised machine cannot decrypt
secrets meant for a different machine.

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
├── soyo.age.pub            # Soyo host public key (plaintext; placeholder
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

The `age.rekey.hostPubkey` option defaults to a well-known dummy age public
key for which **no one has the private key**.  When the system sees this
dummy key during `nix build`, it does not look for real rekeyed files.
Instead it auto-generates **placeholder secrets** — dummy encrypted files
that satisfy the build but cannot actually be decrypted.

This allows:

1. Build and deploy the system (the placeholders get copied to the target).
2. During activation, decryption **fails** (expected — placeholder secrets
   cannot be decrypted by the real host key either).
3. A one-time manual step creates or copies the real password hashes onto
   the target, and the system boots without secrets.

Then:

4. ssh-to-age on the target to get the real host pubkey.
5. Save it as `secrets/soyo.age.pub`.
6. Set `hostPubkey = ../../secrets/soyo.age.pub;` in the host assembler.
7. Run `agenix rekey` to produce real rekeyed files.
8. Redeploy — now the target can decrypt them.

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
nix --extra-experimental-features 'nix-command flakes' \
  develop '.#' -c agenix edit secrets/root-password.age

# 3. Rekey so the change propagates to host-specific rekeyed files
nix --extra-experimental-features 'nix-command flakes' \
  develop '.#' -c agenix rekey

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
     | nix shell nixpkgs#age -c age --encrypt \
       -r "$(cat secrets/krzysiek.age.pub)" \
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
3. On the target (or a one-time bootstrap key):
   - Generate an SSH host key.
   - Derive its age public key with `ssh-to-age`.
4. Save the pubkey as `secrets/<host>.age.pub`.
5. In the host assembler, set `age.rekey.hostPubkey = ../../secrets/<host>.age.pub;`.
6. Run `agenix rekey` — it will rekey all secrets for the new host.
7. Deploy.

---

## Reference: key files and where they live

| File | Purpose | Created by |
|---|---|---|
| `~/.ssh/id_ed25519` | Master **private** key (YOUR SSH key) | `ssh-keygen` on your workstation |
| `~/.ssh/id_ed25519.pub` | Master public key | same |
| `secrets/krzysiek.age.pub` | Master age public key, stored in repo | `ssh-to-age < ~/.ssh/id_ed25519.pub` (one-time setup) |
| `secrets/soyo.age.pub` | Soyo's age public key | `ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub` during install |
| `/persist/etc/ssh/ssh_host_ed25519_key` | Soyo's SSH host **private** key | `ssh-keygen` during first install |
| `/persist/etc/ssh/ssh_host_ed25519_key.pub` | Soyo's SSH host public key | same |
| `secrets/*.age` | Master-encrypted secrets | `agenix edit ...` or `age --encrypt ...` |
| `secrets/rekeyed/<host>/*.age` | Host-specific rekeyed secrets | `agenix rekey` |

---

## Further reading

- [age encryption format](https://age-encryption.org)
- [agenix](https://github.com/ryantm/agenix) — NixOS module for age secrets
- [agenix-rekey](https://github.com/oddlama/agenix-rekey) — rekeyFile flow
- [ssh-to-age](https://github.com/Mic92/ssh-to-age) — SSH → age key conversion
