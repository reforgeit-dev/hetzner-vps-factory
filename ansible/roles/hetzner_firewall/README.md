# Hetzner Firewall Role

Applies Hetzner Cloud firewall to block public SSH (Tailscale-only access).

## What It Does

- Creates/updates Hetzner Cloud firewall via `hcloud` CLI
- Blocks all inbound traffic except Tailscale UDP and ICMP
- Verifies Tailscale SSH works before applying (safety check)
- Attaches firewall to specified server

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `firewall_name` | `"tailscale-only"` | Firewall name in Hetzner |
| `hetzner_server_name` | `{{ inventory_hostname }}` | Server to apply to |
| `verify_tailscale_ssh` | `true` | Verify Tailscale before applying |
| `enable_hetzner_firewall` | `false` | Must be true to apply |

## Firewall Rules

| Direction | Protocol | Port | Source | Description |
|-----------|----------|------|--------|-------------|
| Inbound | UDP | 41641 | 0.0.0.0/0 | Tailscale |
| Inbound | ICMP | - | 0.0.0.0/0 | Ping |

**SSH (port 22) is NOT allowed** - access via Tailscale only.

## Usage

```bash
# Apply firewall lockdown
ansible-playbook -i inventory.ini playbooks/site.yml -t lockdown \
  -e '{"enable_hetzner_firewall": true}'
```

## Recovery If Locked Out

1. Go to Hetzner Console → Firewalls → `tailscale-only`
2. Add rule: TCP 22 from 0.0.0.0/0
3. SSH via public IP and fix issue
4. Remove TCP 22 rule

## Notes

- Requires `hcloud` CLI installed locally
- Requires `HCLOUD_TOKEN` environment variable
- Safety check verifies Tailscale SSH before blocking public SSH
- This is the final step in "lockdown mode"
- Role has `never` tag - only runs when explicitly requested
