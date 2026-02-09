# Hetzner VPS Factory

Terraform + Ansible toolkit for provisioning Hetzner Cloud VPS instances. Designed for **homelab use** — personal servers, self-hosted services, side projects. Not production-hardened, but tested on real deployments and good enough to run actual workloads.

Tested on Ubuntu 24.04 (with upgrades through 25.10). Other operating systems have not been tested.

## Why This Exists

You can SSH into a VPS and set everything up by hand. You can ask an LLM to walk you through it. You'll get a working server — until you hit the first weird failure at 2am and spend an hour debugging.

This repo is the result of actually doing that, multiple times, on real deployments. The problems below are already solved:

**Security that's easy to skip manually:**
- SSH key-only auth with fail2ban (3 strikes, 1hr ban)
- Kernel hardening via sysctl (ASLR, SYN flood protection, ICMP redirects disabled)
- UFW firewall with rate-limited SSH + Tailscale-only access
- Unattended security upgrades with auto-reboot
- Hetzner Cloud firewall lockdown that blocks all public access except Tailscale UDP

**Gotchas already handled:**
- fail2ban bans Coolify's own Docker containers (172.16.0.0/12 must be whitelisted) — manifests as "Server is not reachable" with no useful error
- Tailscale-only domains can't use Let's Encrypt HTTP challenge — needs Cloudflare DNS challenge, which isn't the default
- Several other Coolify, SSHFS, and Docker Compose quirks documented in the setup guide

**Reproducibility:**
- `./scripts/deploy.sh` rebuilds the entire stack from scratch in ~15 minutes
- Every role is idempotent — safe to re-run after failures or changes
- Server is disposable — terraform destroy + deploy.sh = clean slate
- All configuration is in version-controlled files, not in someone's head or a wiki

**Time saved:**

All of the following is handled by `deploy.sh`:

| Task | Manual time (SSH + docs) |
|------|--------------------------|
| SSH key-only auth, disable password | 15-30 min |
| fail2ban install + configure | 20-30 min |
| Kernel hardening (sysctl) | 30-60 min |
| UFW firewall + unattended upgrades | 20-30 min |
| Non-root user with sudo | 10-15 min |
| Swap file setup + tuning | 10-15 min |
| Docker + Compose V2 | 15-30 min |
| Tailscale install + auth | 10-15 min |
| Storage Box SSHFS + fstab + reconnect | 1-2 hours |
| Hetzner Cloud firewall (Tailscale-only) | 15-30 min |
| Coolify install (dirs, compose, SSH key) | 1-2 hours |
| Ubuntu version upgrade | 30-60 min |
| **Total** | **~8-12 hours** |

The ~30 minutes of manual steps left (Coolify admin account, SSL config, Immich deploy via UI) are documented step-by-step in the setup guide.

## Project Structure

```
hetzner-vps-factory/
├── terraform/
│   ├── main.tf                    # SSH key + module call (module.vps)
│   ├── modules/hetzner-vps/       # Reusable VPS module (server + optional storagebox)
│   ├── envs/immich.tfvars.example  # Profile config template (copy to .tfvars)
│   ├── backend.tf                 # S3 backend for state storage
│   ├── provider.tf                # Hetzner Cloud, TLS, Random providers
│   ├── variables.tf               # Input variables with validation
│   └── outputs.tf                 # Proxied outputs from module
│
├── ansible/
│   ├── ansible.cfg                # Runtime config (pipelining, fact caching)
│   ├── inventory.ini              # Auto-generated host inventory
│   ├── group_vars/
│   │   ├── all.yml                # Universal defaults (all profiles)
│   │   └── immich.yml             # Immich profile overrides
│   ├── host_vars/                 # Auto-generated (storagebox credentials)
│   ├── playbooks/
│   │   ├── site.yml               # Main orchestrator playbook
│   │   ├── base.yml               # Core security only (no Docker/Tailscale)
│   │   └── upgrade.yml            # Ubuntu version upgrade
│   └── roles/
│       ├── common/                # Base packages, unattended-upgrades
│       ├── ssh/                   # SSH hardening
│       ├── fail2ban/              # Brute-force protection
│       ├── sysctl/                # Kernel hardening
│       ├── users/                 # Power user and apps user
│       ├── ufw/                   # Host firewall
│       ├── swap/                  # Swap file configuration
│       ├── docker/                # Docker and Compose V2 (optional)
│       ├── tailscale/             # Tailscale VPN (optional)
│       ├── storagebox/            # Hetzner Storage Box SSHFS mounting
│       ├── coolify/               # Coolify self-hosted PaaS (optional)
│       ├── upgrade/               # Ubuntu release upgrade
│       └── hetzner_firewall/      # Cloud firewall lockdown
│
├── scripts/
│   ├── deploy.sh                  # Automated deployment with --profile
│   └── generate_inventory.sh      # Generate inventory + host_vars
│
└── docs/
    ├── reference/                 # How things work today
    │   └── SECURITY.md            # Security hardening reference
    └── examples/                  # Real deployment examples
        └── COOLIFY_IMMICH_SETUP.md
```

## Prerequisites

- Terraform >= 1.0
- Ansible >= 2.9
- jq, hcloud CLI
- SSH key pair (`~/.ssh/id_ed25519`)
- A domain with a DNS provider that supports ACME DNS challenge — needed for SSL on Tailscale-only domains (HTTP challenge can't reach Tailscale IPs). Tested with **Cloudflare**. Any provider supported by [LEGO](https://go-acme.github.io/lego/dns/) (100+) should work — avoid GoDaddy (API access restrictions). See [Traefik DNS challenge docs](https://doc.traefik.io/traefik/reference/install-configuration/tls/certificate-resolvers/acme/).

```bash
# Required — also available as TF_VAR_ to avoid placing in .tfvars:
export HCLOUD_TOKEN="your-hetzner-api-token"          # used by hcloud CLI
export TF_VAR_hcloud_token="your-hetzner-api-token"   # used by Terraform provider
export TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"           # used by Ansible
export TF_VAR_tailscale_auth_key="tskey-auth-xxxxx"   # used by Terraform (if needed)
```

### Terraform State Backend

S3 backend (`terraform/backend.tf`) is optional but recommended for shared/persistent state. To use local state instead, remove or comment out `backend.tf` and run `terraform init`.

## Quick Start

```bash
# 1. Copy and customize the profile tfvars
cp terraform/envs/immich.tfvars.example terraform/envs/immich.tfvars
# Edit terraform/envs/immich.tfvars with your server_name, server_type, etc.

# 2. Deploy (immich profile by default)
./scripts/deploy.sh
```

### Deploy Options

```bash
./scripts/deploy.sh                          # Full deployment (interactive)
./scripts/deploy.sh --profile immich         # Explicit profile
./scripts/deploy.sh --skip-terraform         # Ansible only (existing infra)
./scripts/deploy.sh --skip-ansible           # Terraform only
./scripts/deploy.sh --quiet --auto-approve   # Full automation (no prompts)
```

## VPS Profiles

Profiles control what gets deployed to each VPS. Each profile has:
- `terraform/envs/<profile>.tfvars` — infrastructure config
- `ansible/group_vars/<profile>.yml` — Ansible variable overrides
- Auto-generated `ansible/host_vars/<hostname>.yml` — storagebox credentials

Ansible variable precedence: role defaults < `group_vars/all.yml` < `group_vars/<profile>.yml` < `host_vars/`

> **Current limitation — single profile per deployment.** The tooling manages one VPS at a time. Terraform uses a single module call with a shared backend state — running `deploy.sh` with a different profile would **destroy the existing VPS** and create a new one, since Terraform sees different resource attributes in the same state file. The Ansible playbooks and roles are multi-host capable, but the scripts (`deploy.sh`, `generate_inventory.sh`) and Terraform layer (single module, scalar outputs, one state key) only support one profile. Full multi-VPS orchestration (workspaces or `for_each`, map outputs, inventory merging) is not yet implemented.

### Ansible Configuration

`group_vars/all.yml` contains universal defaults shared by all profiles (e.g., `power_user_name`). Profile-specific overrides go in `group_vars/<profile>.yml`.

Key variables to set per profile:

| Variable | Required | Description |
|----------|----------|-------------|
| `tailscale_hostname` | Yes | Tailscale MagicDNS hostname for the VPS |
| `hetzner_server_name` | Yes | Must match `server_name` in the profile's `.tfvars` |
| `install_coolify` | No | Enable Coolify PaaS (also requires `disable_root_ssh: false`) |
| `disable_root_ssh` | No | Must be `false` if using Coolify |
| `storagebox_directories` | No | Directories to create on the Storage Box mount |

See `group_vars/immich.yml` for a complete example.

### Adding a New Profile

1. Copy `terraform/envs/immich.tfvars.example` to `terraform/envs/<name>.tfvars` and customize
2. Create `ansible/group_vars/<name>.yml` with profile overrides (see table above)
3. Update `terraform/backend.tf` — change the state `key` to avoid overwriting an existing profile's state
4. Deploy: `./scripts/deploy.sh --profile <name>`

## Configuration

### Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `server_name` | `my-server` | VPS hostname |
| `server_type` | `cx33` | Hetzner server type |
| `location` | `hel1` | Datacenter |
| `os_image` | `ubuntu-24.04` | Operating system |
| `backups_enabled` | `true` | Automatic daily backups |
| `storagebox_enabled` | `true` | Provision Storage Box |
| `storagebox_type` | `bx11` | Storage Box type (100GB-10TB) |

### Optional Roles

```yaml
# In group_vars/<profile>.yml or group_vars/all.yml
install_docker: false     # Skip Docker
install_tailscale: false  # Skip Tailscale
install_swap: false       # Skip swap
install_coolify: true     # Install Coolify PaaS (requires Docker, root SSH)
```

## What Gets Deployed

**Infrastructure** (Terraform): Hetzner VPS + SSH key + optional Storage Box (100GB-10TB) with auto-generated SSH keypair. Daily backups with 7-day retention.

**Configuration** (Ansible):
- Security hardening: SSH key-only auth, fail2ban, sysctl kernel hardening, UFW firewall
- Users: power user with sudo, apps user for services
- Swap: configurable swap file with tuned swappiness
- Docker + Compose V2 with log rotation
- Tailscale VPN with auto-authentication
- Storage Box SSHFS mount with auto-reconnect
- Coolify self-hosted PaaS (optional, for deploying services like Immich)
- Optional Hetzner Cloud firewall lockdown (Tailscale-only access)

## Troubleshooting

**Terraform init fails**: Check S3 backend credentials, or remove `backend.tf` to use local state.

**Ansible connectivity fails**: Wait for VPS boot, check SSH key permissions, re-run `./scripts/generate_inventory.sh`.

**SSH fails on brand-new server**: Hetzner VPS needs ~15-30 seconds after creation before SSH is ready. Both `deploy.sh` and `generate_inventory.sh --mode auto` will automatically retry for up to 30 seconds (3 attempts, 10s apart) while waiting for SSH to become available.

**Locked out (firewall)**: Hetzner Console -> Firewalls -> `tailscale-only` -> Add TCP 22 from 0.0.0.0/0 -> SSH in -> Fix -> Remove rule.

## Documentation

| Document | Description |
|----------|-------------|
| `CLAUDE.md` | Development guidance and common commands |
| `docs/reference/SECURITY.md` | Security hardening reference |
| `docs/examples/COOLIFY_IMMICH_SETUP.md` | Coolify + Immich setup example |

## Cost (per VPS)

| Resource | Smaller setup | Immich setup |
|----------|--------------|--------------|
| VPS | cx22 (2 vCPU, 4GB) €3.68 | cx33 (4 vCPU, 8GB) €6.14 |
| Backups (+20%) | €0.74 | €1.23 |
| Storage Box | bx11 (100GB) €3.94 | bx21 (1TB) €13.41 |
| **Total** | **€8.36** | **€20.78** |

Prices from hel1 datacenter, Feb 2026. cx22 is enough for lightweight services. Immich with machine learning needs cx33 or higher. See [Hetzner Cloud pricing](https://www.hetzner.com/cloud) for current rates.
