# UFW Role

Configures UFW (Uncomplicated Firewall) for host-level protection.

## What It Does

- Sets default deny incoming, allow outgoing policy
- Opens SSH and Tailscale ports
- Enables SSH rate limiting
- Whitelists localhost and Docker subnets from rate limiting

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ufw_default_incoming` | `deny` | Default incoming policy |
| `ufw_default_outgoing` | `allow` | Default outgoing policy |
| `ufw_allow_rules` | SSH + Tailscale | Ports to open |
| `ufw_rate_limit_ssh` | `true` | Rate limit SSH connections |
| `ufw_ssh_port` | `22` | SSH port for rate limiting |
| `ufw_ssh_whitelist_subnets` | `[127.0.0.0/8, 172.16.0.0/12]` | Skip rate limit for these |
| `ufw_logging` | `true` | Enable UFW logging |

## Default Allowed Ports

| Port | Protocol | Service |
|------|----------|---------|
| 22 | TCP | SSH |
| 41641 | UDP | Tailscale |

## Usage

```bash
# Run only UFW setup
ansible-playbook -i inventory.ini playbooks/site.yml -t ufw

# Check status on server
sudo ufw status verbose
```

## Adding Ports

```yaml
# group_vars/all.yml
ufw_allow_rules:
  - { port: 22, proto: tcp }
  - { port: 41641, proto: udp }
  - { port: 443, proto: tcp }   # Add HTTPS
  - { port: 80, proto: tcp }    # Add HTTP
```

## Notes

- Rate limiting blocks IPs making too many connections quickly
- Docker subnet whitelist prevents container connectivity issues
- Works alongside fail2ban for defense in depth
