# deploy-garage

A shell-based automation tool for securely deploying [Garage](https://garagehq.deuxfleurs.fr/) (distributed object storage) as a containerised Docker application on cloned Ubuntu Server instances. It handles full-disk encryption key rotation, network-bound decryption, SSH hardening, and Docker payload delivery — so you can go from a fresh clone to a running node with minimal manual configuration.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Adapting for Your Own Deployment](#adapting-for-your-own-deployment)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

When deploying multiple nodes from a single VM template, each clone inherits the same disk encryption keys, machine identifiers, and credentials. This creates serious security and operational issues — a compromise of one node's encryption key effectively compromises every clone.

**deploy-garage** solves this by automating the entire post-clone provisioning process. After running a single script, each node receives unique credentials, a freshly rotated LUKS encryption key, network-bound automatic decryption via Clevis/Tang, locked-down SSH access, and a ready-to-start Garage + Caddy Docker stack.

---

## Features

**Identity & Credential Rotation** — Replaces machine-level unique identifiers (machine-id, hostname, SSH identity, etc.) so that each clone is distinct. Generates unique passwords for both login and disk encryption, and rotates the LUKS volume key so that knowledge of the template's passphrase cannot decrypt any deployed clone.

**Network-Bound Disk Encryption** — Configures Clevis/Tang so that LUKS volumes are automatically unlocked at boot when the machine can reach your Tang servers, removing the need for manual passphrase entry on every reboot.

**SSH Hardening** — Deploys only your specified public keys and disables password-based SSH authentication, ensuring that only authorised keyholders can access the node.

**Docker Payload Delivery** — Copies a pre-configured `docker-compose.yml`, Garage configuration template, and Caddy reverse-proxy configuration into place, leaving you with a stack that is ready to pull and start with minimal configuration.

**Minimally Attended Operation** — The entire process runs via a single `init.sh` invocation with no interactive prompts and no parameters. The node reboots automatically when finished. If you fork and set your site-specific values, all you need to do after setup is set a few secrets and start docker.

---

## Repository Structure

```
deploy-garage/
├── init.sh                      # Main entry point — run this after cloning
├── scripts/                     # Modular shell scripts called by init.sh
├── config/
│   ├── tang.json                # Tang server configuration for Clevis/NBDE
│   └── garage-nodes.list        # Bootstrap peer addresses for Garage
├── ephemeral/                   # Temporary credential files
│   ├── *.pw                     # Default password files
│   ├── *.txt                    # Generated password and other unique files - after deployment
│   ├── id_ed25519               # Generated ssh privkey - after deployment
│   └── id_ed25519.pub           # Generated ssh pubkey - after deployment
├── keys/                        # SSH public keys to be authorised on the node
├── payload/
│   ├── garage/
│   │   ├── docker-compose.yml   # Docker compose configuration file — edit before deployment
│   │   └── garage.template.toml # Garage configuration file — edit before deployment
│   └── caddy/
│       └── conf/
│           └── Caddyfile        # Caddy configuration file — edit before deployment
└── .gitignore
```

---

## Prerequisites

**Base Image Requirements** — You need a template VM (or install) of Ubuntu Server 24.04 LTS with the following already in place: OpenSSH server installed, Git installed (installable via `sudo apt install git`), and LUKS full-disk encryption enabled with the default passphrases described below.

**Default Credentials** — The script expects the cloned image to use `default-luks-key` as the LUKS passphrase and `default-login-key` as the root/login password. If your template uses different defaults, update the corresponding `.pw` files in the `ephemeral/` directory before running the script. Note that `.pw` files must **not** end with a trailing newline; use `printf "your-password" > filename.pw` to create them safely.

**Tang Server** — At least one [Tang](https://github.com/latchset/tang) server must be reachable on your network for network-bound decryption to function.

**Hypervisor / Network Access** — You will need a way to identify the DHCP-assigned IP address of the node after it reboots (e.g., via your hypervisor console or DHCP lease table).

---

## Quick Start

**1. Clone the repository onto your target machine**

```bash
sudo apt install git -y   # if not already installed
git clone https://github.com/maashaw/deploy-garage.git ~/deploy-garage
```

**2. Configure pre-run settings**

Edit `~/deploy-garage/config/tang.json` to point to your Tang server(s) for network-bound LUKS decryption.

Place your SSH public key(s) into `~/deploy-garage/keys/`. Remove any keys that are not yours — these will be the **only** keys granted access after deployment.

If your template image uses non-default LUKS or login passwords, update the `.pw` files in `~/deploy-garage/ephemeral/` accordingly.

**3. Run the script**

```bash
cd ~/deploy-garage
./init.sh
```

No arguments are required. The script generates all new passwords, encryption keys, and machine identifiers automatically.

**4. Wait for completion**

The script will re-encrypt the full disk with a new LUKS key, which is the most time-consuming step. When it finishes, the machine will **reboot automatically**.

**5. Connect via SSH**

After the reboot, connect to the node's DHCP-assigned address using the SSH key you placed in `keys/`. The generated credentials are stored in `~/deploy-garage/ephemeral/` on the node — record them somewhere secure, then destroy the originals:

```bash
shred -u ~/deploy-garage/ephemeral/*
```

---

## Post-Deployment Configuration

Once you have SSH access to the deployed node, a small amount of application-level configuration is required before starting the stack.

**Garage** — Edit `~/garage/vols/garage.toml` to add your `bootstrap_peers` if they are not already populated, and review the rest of the file to confirm the replication factor, data directory, and API/web settings match your environment.

**Caddy** — Edit `~/caddy/config/Caddyfile` to set your domain name and any DNS challenge parameters. If you are using DNS-based ACME challenges, also add your DNS provider API key to `~/garage/docker-config.yml`.

**Start the stack**

```bash
sudo docker compose --file ~/garage/docker-compose.yml pull
sudo docker compose --file ~/garage/docker-compose.yml up -d
```

---

## Adapting for Your Own Deployment

This repository is structured so that you can swap out the Garage + Caddy payload for your own Docker application with minimal changes.

Prepare a base Ubuntu Server 24.04 LTS image with OpenSSH, Git, and LUKS full-disk encryption enabled. Replace the SSH public keys in `keys/` with your own. Update `config/tang.json` with your Tang server addresses and `config/garage-node.list` with your bootstrap nodes (or remove references to it if not applicable). Swap or modify the Docker Compose file at `payload/garage/docker-compose.yml`, the Garage template at `payload/garage/garage.template.toml`, and the Caddyfile at `payload/caddy/conf/Caddyfile` to suit your application. The scripts in `scripts/` are modular, so you can disable or extend individual provisioning steps as needed.

---

## Security Considerations

**Credential lifecycle** — The `ephemeral/` directory contains plaintext passwords. On the template image these are the well-known defaults; on a deployed node they are the newly generated secrets. Always `shred` this directory after recording credentials in a proper secrets manager.

**Key rotation** — The LUKS volume master key is rotated during provisioning so that access to the template image's passphrase does not grant decryption of any deployed clone. This is critical in multi-tenant or shared-infrastructure environments.

**SSH surface** — After deployment, password authentication is disabled and only the keys you explicitly placed in `keys/` are authorised. Verify that this directory contains only your intended keys before running `init.sh`, or you risk locking yourself out permanently.

**Tang availability** — If all configured Tang servers become unreachable, the node will not be able to unlock its disk on reboot, and you will need to access it through your hypervisor to boot. Ensure you have redundant Tang servers or retain a copy of the LUKS passphrase for emergency recovery.

---

## Troubleshooting

**Node does not unlock after reboot** — Verify that the Tang server is reachable from the node's network and that `tang.json` contains the correct address and port. If this problem occurs on initial deployment, it will not be possible to unlock the machine without Tang. After first use, you can use the LUKS key retrieved from `ephemeral/` to manually unlock the machine via the hypervisor console.

**SSH connection refused after deployment** — Confirm that you placed the correct public key in `keys/` before running `init.sh`. If this problem occurs on initial deployment, it will not be possible to access the machine. After first use, you can use the user key retrieve from `ephemeral/` to manually log into the machine via the hypervisor console.

**Disk re-encryption is slow** — This is expected. LUKS re-encryption is an I/O-intensive operation that must read and rewrite every block on the encrypted volume. Duration depends on disk size and storage backend performance. Consider provisioning the disk at a minimal size initially, and expanding the disk as required after provisioning.

---

## License

This project is licensed under GPLv3
