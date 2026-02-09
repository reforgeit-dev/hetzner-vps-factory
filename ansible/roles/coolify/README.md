# Coolify Role

Installs [Coolify](https://coolify.io) self-hosted PaaS using the manual installation method (works on non-LTS Ubuntu).

## What It Does

- Creates Coolify data directories under `/data/coolify/`
- Downloads compose files from Coolify CDN
- Templates `.env` with auto-generated secrets (first run only)
- Creates Docker network and starts Coolify containers
- Waits for Coolify to become healthy

## Prerequisites

- Docker must be installed (docker role)
- Root SSH access must be enabled (`disable_root_ssh: false`)
- Docker subnets (`172.16.0.0/12`) must be in fail2ban's `ignoreip` — Coolify SSHs to the host from inside a container, and failed attempts during setup will trigger a ban otherwise

## Post-Install (manual)

1. Access `http://<tailscale-hostname>:8000` and create admin account
2. Complete the setup wizard — choose "Deploy on this server"
3. Coolify generates its own SSH key and authorizes it for root during setup

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `install_coolify` | `false` | Enable Coolify installation |
| `coolify_cdn_url` | `https://cdn.coollabs.io/coolify` | CDN for compose files |
| `coolify_data_dir` | `/data/coolify` | Coolify data directory |
| `coolify_port` | `8000` | Web UI port |
| `disable_root_ssh` | `true` | Must be `false` for Coolify |

## Usage

```bash
# Run only Coolify setup
ansible-playbook -i inventory.ini playbooks/site.yml -t coolify

# Skip Coolify installation
ansible-playbook -i inventory.ini playbooks/site.yml -e 'install_coolify=false'
```

## Verification

```bash
# Check containers
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep coolify

# Access dashboard
curl -I http://localhost:8000
```

## Notes

- This role is optional: set `install_coolify: true` to enable (default: false)
- Secrets in `.env` are generated once on first run and never overwritten
- Coolify admin account must be created manually via the web UI
- Coolify updates itself via its own dashboard (Settings > Update)
- Uses the manual install method from [Coolify docs](https://coolify.io/docs/get-started/installation#manually)
