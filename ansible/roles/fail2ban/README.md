# fail2ban Role

Installs and configures fail2ban for SSH brute-force protection.

## What It Does

- Installs fail2ban package
- Configures SSH jail with customizable settings
- Whitelists Tailscale CGNAT range to prevent self-lockout

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `fail2ban_maxretry` | `3` | Failed attempts before ban |
| `fail2ban_bantime` | `3600` | Ban duration (seconds, 1 hour) |
| `fail2ban_findtime` | `600` | Time window for counting failures (10 min) |
| `fail2ban_ignoreip` | `127.0.0.1/8 ::1 100.64.0.0/10` | IPs to never ban |

## Usage

```bash
# Run only fail2ban setup
ansible-playbook -i inventory.ini playbooks/site.yml -t fail2ban

# Check fail2ban status on server
sudo fail2ban-client status sshd
```

## Templates

- `templates/jail.local.j2` - fail2ban SSH jail configuration

## Notes

- The Tailscale CGNAT range (100.64.0.0/10) is whitelisted by default
- This prevents lockout when connecting via Tailscale VPN
- Jail config is written to `/etc/fail2ban/jail.local`
