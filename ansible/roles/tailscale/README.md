# Tailscale Role

Installs and configures Tailscale VPN client.

## What It Does

- Adds Tailscale repository and GPG key
- Installs Tailscale client
- Authenticates with provided auth key
- Registers with custom hostname

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tailscale_auth_key` | `$TAILSCALE_AUTH_KEY` | Auth key (from env) |
| `tailscale_hostname` | `{{ ansible_hostname }}` | Hostname in Tailscale |
| `tailscale_extra_args` | `""` | Additional `tailscale up` flags |

## Usage

```bash
# Run only Tailscale setup
ansible-playbook -i inventory.ini playbooks/site.yml -t tailscale

# Skip Tailscale installation
ansible-playbook -i inventory.ini playbooks/site.yml -e 'install_tailscale=false'
```

## Environment

Requires `TAILSCALE_AUTH_KEY` environment variable:

```bash
export TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"
```

Get auth keys from: https://login.tailscale.com/admin/settings/keys

## Verification

```bash
tailscale status
tailscale ip
```

## Notes

- This role is optional: set `install_tailscale: false` to skip
- Recommended hostname pattern: `<server>-<location>-<provider>`
- Example: `my-server-hel-hetzner`
