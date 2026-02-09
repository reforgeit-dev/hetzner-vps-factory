# CLAUDE.md

Guidance for Claude Code when working with this repository.

## Project Overview

**VPS factory** — Terraform + Ansible toolkit for provisioning Hetzner Cloud VPS instances with different configurations. Each VPS is a "profile" (e.g., `immich` for Coolify + Immich, future profiles for clawdbot, dev-only, etc.).

## File Structure

**Terraform** (`terraform/`):
- `main.tf` - SSH key (shared) + `module "vps"` call
- `modules/hetzner-vps/` - Reusable module: server + optional storagebox (`count`-gated)
- `envs/immich.tfvars.example` - Profile config template (copy to `.tfvars` and customize)
- `provider.tf` - Hetzner Cloud, TLS, Random providers
- `backend.tf` - S3 backend state storage
- `variables.tf` - Input variables with validation
- `outputs.tf` - Proxied from module (names must not change — scripts depend on them)

**Ansible** (`ansible/`):
- `ansible.cfg` - Runtime config (pipelining, fact caching)
- `inventory.ini` - Auto-generated host inventory (gitignored)
- `group_vars/all.yml` - Universal defaults (all profiles)
- `group_vars/immich.yml` - Immich profile overrides
- `host_vars/` - Auto-generated from terraform outputs (gitignored, contains storagebox credentials)
- `playbooks/site.yml` - Main orchestrator playbook
- `playbooks/base.yml` - Core security hardening only (no Docker/Tailscale)
- `playbooks/upgrade.yml` - Ubuntu version upgrade
- Roles: common, ssh, fail2ban, sysctl, users, ufw, swap, docker, tailscale, storagebox, coolify, upgrade, hetzner_firewall

**Scripts** (`scripts/`):
- `deploy.sh` - Automated deployment with `--profile` flag
- `generate_inventory.sh` - Generate inventory + host_vars from terraform outputs

**Documentation** (`docs/`):
- `reference/SECURITY.md` - Security hardening reference
- `examples/COOLIFY_IMMICH_SETUP.md` - Coolify and Immich setup example
- `planning/IMPROVEMENT_IDEAS.md` - Tracked improvement ideas
- `planning/BACKUP_GLACIER_PLAN.md` - S3 Glacier backup strategy

## Deployment

### Automated Deployment

```bash
./scripts/deploy.sh                          # Full deployment (immich profile)
./scripts/deploy.sh --profile immich         # Explicit profile
./scripts/deploy.sh --skip-terraform         # Ansible only
./scripts/deploy.sh --skip-ansible           # Terraform only
./scripts/deploy.sh --quiet --auto-approve   # Full automation (no prompts)
```

The script:
1. Runs Terraform (init, validate, plan)
2. Skips apply if no changes, prompts if changes detected
3. Auto-detects server state via SSH connectivity tests
4. Generates inventory + host_vars (storagebox credentials)
5. Runs Ansible provisioning
6. Offers Ubuntu upgrade and firewall lockdown

### Environment Variables

```bash
export HCLOUD_TOKEN="your-hetzner-token"
export TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"
```

## VPS Profile System

Profiles control per-deployment configuration:
- `terraform/envs/<profile>.tfvars` — infrastructure config (server type, location, storagebox)
- `ansible/group_vars/<profile>.yml` — Ansible variable overrides
- `ansible/host_vars/<hostname>.yml` — auto-generated storagebox credentials

Variable precedence: role defaults < `group_vars/all.yml` < `group_vars/<profile>.yml` < `host_vars/`

Inventory uses child groups: `[immich]` under `[hetzner_vps:children]`. Playbooks target `hetzner_vps` so they work across all profiles.

## Ansible Workflow

### Role Order (site.yml)

common -> ssh -> fail2ban -> sysctl -> users -> ufw -> swap -> docker -> tailscale -> storagebox -> coolify

Optional roles gated by variables: `install_docker`, `install_tailscale`, `install_swap` (all default true), `install_coolify` (default false).

### Role Defaults

Each role has `defaults/main.yml`. Key variables:

| Role | Key Variables |
|------|---------------|
| common | `apt_packages`, `unattended_upgrades_enabled`, `unattended_upgrades_auto_reboot` |
| ssh | `ssh_password_authentication`, `ssh_max_auth_tries`, `ssh_x11_forwarding` |
| fail2ban | `fail2ban_maxretry`, `fail2ban_bantime`, `fail2ban_ignoreip` |
| sysctl | `sysctl_hardening_enabled`, `sysctl_network_hardening`, `sysctl_kernel_hardening` |
| users | `power_user_name`, `power_user_groups`, `apps_user_home` |
| swap | `swap_file_size_mb`, `swap_swappiness`, `swap_vfs_cache_pressure` |
| docker | `docker_log_max_size`, `docker_log_max_file`, `docker_packages` |
| tailscale | `tailscale_hostname`, `tailscale_extra_args` |
| ufw | `ufw_allow_rules`, `ufw_rate_limit_ssh`, `ufw_default_incoming` |
| storagebox | `storagebox_mount_point`, `storagebox_ssh_port`, `storagebox_directories` |
| coolify | `coolify_port`, `coolify_data_dir`, `coolify_cdn_url` |

### Common Commands

```bash
# Full deployment
ansible-playbook -i inventory.ini playbooks/site.yml

# Core security only
ansible-playbook -i inventory.ini playbooks/base.yml

# Specific role
ansible-playbook -i inventory.ini playbooks/site.yml -t docker
ansible-playbook -i inventory.ini playbooks/site.yml -t sysctl

# All security roles
ansible-playbook -i inventory.ini playbooks/site.yml -t security

# Apply lockdown (blocks public SSH)
ansible-playbook -i inventory.ini playbooks/site.yml -t lockdown -e '{"enable_hetzner_firewall": true}'

# Ubuntu upgrade
ansible-playbook -i inventory.ini playbooks/upgrade.yml
```

### Lockdown Mode

Applies Hetzner Cloud firewall blocking public SSH. **Recovery if locked out**:
1. Hetzner Console -> Firewalls -> `tailscale-only`
2. Add rule: TCP 22 from 0.0.0.0/0
3. SSH via public IP, fix issue
4. Remove TCP 22 rule

## Terraform Commands

```bash
terraform init
terraform validate
terraform plan -var-file=envs/immich.tfvars
terraform apply -var-file=envs/immich.tfvars
terraform fmt -recursive
terraform state list
```

## Important Considerations

- **Terraform output names must not change** — `deploy.sh` and `generate_inventory.sh` read them by name
- **SSH key stays in root terraform** — shared across all VPS instances, not in the module
- **Storagebox credentials flow via host_vars** — auto-generated by `generate_inventory.sh` from terraform outputs, no temp files
- **Hetzner Firewall stays in Ansible** — Terraform runs first and needs SSH, Ansible configures Tailscale then applies firewall
- **Storage Box uses port 23** — not 22; the storagebox role handles this
- **Ansible performance** — pipelining and fact caching enabled for 2-5x faster execution
- **All operations are idempotent** — safe to re-run
- **Coolify requires `disable_root_ssh: false`** — it SSHs to localhost from inside Docker containers
- **Coolify + fail2ban interaction** — fail2ban must whitelist Docker subnets (`172.16.0.0/12` in `ignoreip`), otherwise Coolify's SSH from containers triggers a ban
- **Coolify quick install only works on Ubuntu LTS** — the role uses the manual installation method which works on any Ubuntu version
- **Coolify admin/services configured via UI** — Ansible installs Coolify; admin account, SSL (Traefik DNS challenge), and service deployments (Immich) are done manually through the Coolify web UI
- **Traefik DNS challenge required for Tailscale-only domains** — HTTP challenge can't reach Tailscale IPs; use Cloudflare DNS challenge with `CF_DNS_API_TOKEN`
- **Immich storagebox subdirectories must pre-exist** — create `encoded-video`, `library`, `profile`, `thumbs`, `upload`, `backups` under the mount before deploying Immich

