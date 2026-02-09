# Hetzner VPS Factory

Terraform + Ansible toolkit for provisioning Hetzner Cloud VPS instances. This is a **VPS factory** — reusable infrastructure that can deploy different configurations (Coolify + Immich, dev boxes, etc.) using profiles.

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
    ├── examples/                  # Real deployment examples
    │   └── COOLIFY_IMMICH_SETUP.md
    └── planning/                  # Future work
        ├── IMPROVEMENT_IDEAS.md   # Tracked improvement ideas
        └── BACKUP_GLACIER_PLAN.md # S3 Glacier backup strategy
```

## Prerequisites

- Terraform >= 1.0
- Ansible >= 2.9
- jq, hcloud CLI
- SSH key pair (`~/.ssh/id_ed25519`)

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
# Deploy (immich profile by default)
./scripts/deploy.sh

# Or with explicit profile
./scripts/deploy.sh --profile immich
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

### Adding a New Profile

1. Copy `terraform/envs/immich.tfvars.example` to `terraform/envs/<name>.tfvars` and customize
2. Create `ansible/group_vars/<name>.yml` with overrides
3. Deploy: `./scripts/deploy.sh --profile <name>`

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
| `docs/planning/IMPROVEMENT_IDEAS.md` | Tracked improvement ideas |
| `docs/planning/BACKUP_GLACIER_PLAN.md` | S3 Glacier backup strategy |

## Cost (per VPS)

| Resource | Monthly |
|----------|---------|
| cx33 VPS (4 vCPU, 8GB) | ~€7 |
| Backups (+20%) | ~€1.40 |
| Storage Box bx11 (100GB) | ~€3.81 |
| **Total** | **~€12.21** |
