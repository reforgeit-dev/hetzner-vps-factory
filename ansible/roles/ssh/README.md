# SSH Role

Hardens SSH configuration for security best practices.

## What It Does

- Disables password authentication (key-only)
- Disables empty passwords
- Limits authentication attempts
- Configures client keepalive
- Disables X11 forwarding

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_password_authentication` | `"no"` | Disable password auth |
| `ssh_permit_empty_passwords` | `"no"` | Disable empty passwords |
| `ssh_max_auth_tries` | `3` | Max auth attempts per connection |
| `ssh_client_alive_interval` | `300` | Keepalive interval (seconds) |
| `ssh_client_alive_count_max` | `2` | Keepalive count before disconnect |
| `ssh_x11_forwarding` | `"no"` | Disable X11 forwarding |

## Usage

```bash
# Run only SSH hardening
ansible-playbook -i inventory.ini playbooks/site.yml -t ssh
```

## Notes

- `PermitRootLogin` is handled by the `users` role after the power user is created
- Restart of SSH service is triggered automatically when config changes
