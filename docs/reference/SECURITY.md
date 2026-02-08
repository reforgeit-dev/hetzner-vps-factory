# Security Roles Reference

This document describes the security hardening applied by each Ansible role.

## Overview

| Role | Purpose | Layer |
|------|---------|-------|
| common | Base packages, unattended-upgrades | Application |
| ssh | SSH hardening | Application |
| fail2ban | Brute-force protection | Application |
| sysctl | Kernel hardening | Kernel |
| ufw | Host firewall | Network (host) |
| tailscale | VPN mesh network | Network (overlay) |
| hetzner_firewall | Cloud firewall | Network (cloud) |

---

## common

Base packages and automatic security updates.

**Configurable in:** `roles/common/defaults/main.yml`

### Unattended Upgrades

| Setting | Value | Why |
|---------|-------|-----|
| `Automatic-Reboot` | true | Apply kernel updates without manual intervention |
| `Automatic-Reboot-Time` | 03:00 | Reboot at low-traffic time |
| `Remove-Unused-Dependencies` | true | Clean up after upgrades |

---

## ssh

SSH daemon hardening. **Configurable in:** `roles/ssh/defaults/main.yml`

| Setting | Value | Why |
|---------|-------|-----|
| `PasswordAuthentication` | no | Keys only - passwords are brute-forceable |
| `PermitEmptyPasswords` | no | Prevent passwordless login |
| `MaxAuthTries` | 3 | Limit brute-force attempts per connection |
| `ClientAliveInterval` | 300s | Detect dead connections |
| `ClientAliveCountMax` | 2 | Disconnect after 10min idle |
| `X11Forwarding` | no | Reduce attack surface |

---

## fail2ban

Blocks IPs after repeated failed SSH attempts. **Configurable in:** `roles/fail2ban/defaults/main.yml`

| Setting | Value | Why |
|---------|-------|-----|
| `maxretry` | 3 | Ban after 3 failed attempts |
| `bantime` | 3600s (1hr) | Temporary ban, not permanent |
| `findtime` | 600s (10min) | Window for counting failures |
| `ignoreip` | `127.0.0.1/8 ::1 100.64.0.0/10` | Whitelist localhost + Tailscale CGNAT |

The Tailscale range (100.64.0.0/10) is whitelisted to prevent locking yourself out when testing via VPN.

---

## sysctl

Kernel-level hardening via `/etc/sysctl.d/99-hardening.conf`.

### Network Security

| Parameter | Value | Why |
|-----------|-------|-----|
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse path filtering - drops spoofed packets |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |
| `net.ipv4.conf.all.accept_redirects` | 0 | Ignore ICMP redirects - prevents MITM |
| `net.ipv4.conf.all.send_redirects` | 0 | Don't send redirects - we're not a router |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Ignore broadcast pings - prevents smurf attacks |
| `net.ipv4.conf.all.accept_source_route` | 0 | Reject source-routed packets |
| `net.ipv4.conf.all.log_martians` | 1 | Log packets with impossible addresses |

Same settings applied to IPv6 (`net.ipv6.conf.*`) where applicable.

### Kernel Security

| Parameter | Value | Why |
|-----------|-------|-----|
| `kernel.randomize_va_space` | 2 | Full ASLR - randomize stack, heap, mmap |
| `kernel.dmesg_restrict` | 1 | Only root can read kernel logs |
| `kernel.kptr_restrict` | 2 | Hide kernel pointers from all users |
| `kernel.sysrq` | 0 | Disable magic SysRq key - prevents console attacks |
| `kernel.yama.ptrace_scope` | 1 | Restrict ptrace to child processes only |

### Filesystem Security

| Parameter | Value | Why |
|-----------|-------|-----|
| `fs.suid_dumpable` | 0 | No core dumps from SUID programs |
| `fs.protected_symlinks` | 1 | Prevent symlink attacks in world-writable dirs |
| `fs.protected_hardlinks` | 1 | Prevent hardlink attacks |

**Configurable in:** `roles/sysctl/defaults/main.yml`

**Disable entirely:** Set `sysctl_hardening_enabled: false`

---

## ufw

Host-level firewall using UFW (Uncomplicated Firewall).

### Default Policy

| Direction | Policy | Why |
|-----------|--------|-----|
| Incoming | DENY | Block all unless explicitly allowed |
| Outgoing | ALLOW | Permit outbound connections |

### Allowed Ports

| Port | Protocol | Service | Why |
|------|----------|---------|-----|
| 22 | TCP | SSH | Remote administration |
| 41641 | UDP | Tailscale | VPN connectivity |

### Rate Limiting

SSH (port 22) has rate limiting enabled - blocks IPs making too many connections in short time. Works alongside fail2ban for defense in depth.

**Configurable in:** `roles/ufw/defaults/main.yml`

**Add ports:**
```yaml
ufw_allow_rules:
  - { port: 22, proto: tcp }
  - { port: 41641, proto: udp }
  - { port: 443, proto: tcp }  # Add HTTPS
```

---

## tailscale

WireGuard-based mesh VPN for secure remote access.

### What It Provides

- **Encrypted tunnel**: All traffic over WireGuard (modern, fast)
- **Zero-trust access**: Devices must be authenticated via Tailscale
- **MagicDNS**: Access server by hostname (e.g., `my-server-hel-hetzner`)
- **NAT traversal**: Works through firewalls without port forwarding

### Authentication

Uses a pre-authenticated key (`TAILSCALE_AUTH_KEY`) for headless setup. Key types:
- **Reusable**: Can provision multiple servers
- **Ephemeral**: Single-use, more secure
- **With tags**: Apply ACLs automatically

### Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `tailscale_hostname` | `{{ ansible_hostname }}` | Name in Tailscale network |
| `tailscale_extra_args` | `""` | Additional flags (e.g., `--accept-routes`) |

**Configurable in:** `roles/tailscale/defaults/main.yml`

---

## hetzner_firewall

Cloud-level firewall applied via Hetzner API. **Blocks public SSH entirely.**

### When Applied

Only runs with tag `lockdown` or when `enable_hetzner_firewall: true`:
```bash
ansible-playbook playbooks/site.yml -t lockdown -e '{"enable_hetzner_firewall": true}'
```

### Firewall Rules

| Direction | Protocol | Port | Source | Description |
|-----------|----------|------|--------|-------------|
| Inbound | UDP | 41641 | 0.0.0.0/0 | Tailscale |
| Inbound | ICMP | - | 0.0.0.0/0 | Ping/diagnostics |

**SSH (port 22) is NOT allowed** - access only via Tailscale.

### Safety Checks

Before applying, the role verifies:
1. Tailscale is running on the server
2. SSH works via Tailscale from the control machine
3. `hcloud` CLI is available locally

### Recovery If Locked Out

1. Hetzner Console → Firewalls → `tailscale-only`
2. Add rule: TCP 22 from 0.0.0.0/0
3. SSH via public IP, fix issue
4. Remove TCP 22 rule

**Configurable in:** `roles/hetzner_firewall/defaults/main.yml`

---

## Defense in Depth

The security roles implement multiple layers:

```
┌─────────────────────────────────────────────────────────────┐
│  Internet                                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Hetzner Cloud Firewall (hetzner_firewall)                  │
│  - Blocks ALL except Tailscale UDP + ICMP                   │
│  - First line of defense, blocks before reaching server     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  UFW Host Firewall (ufw)                                    │
│  - Allows SSH + Tailscale only                              │
│  - Rate limits SSH connections                              │
│  - Backup if cloud firewall misconfigured                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  fail2ban (fail2ban)                                        │
│  - Bans IPs after failed auth attempts                      │
│  - Protects against brute-force                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  SSH Hardening (ssh)                                        │
│  - Key-only authentication                                  │
│  - Limited auth attempts                                    │
│  - Root login disabled                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Kernel Hardening (sysctl)                                  │
│  - ASLR, restricted ptrace                                  │
│  - Network stack hardening                                  │
│  - Protected symlinks/hardlinks                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tailscale VPN (tailscale)                                  │
│  - Encrypted tunnel for all admin access                    │
│  - Device authentication required                           │
│  - Zero-trust network model                                 │
└─────────────────────────────────────────────────────────────┘
```

Each layer compensates for potential failures in others.

---

## Quick Reference

### Apply All Security Roles
```bash
ansible-playbook -i inventory.ini playbooks/site.yml -t security
```

### Apply Specific Role
```bash
ansible-playbook -i inventory.ini playbooks/site.yml -t sysctl
ansible-playbook -i inventory.ini playbooks/site.yml -t ufw
ansible-playbook -i inventory.ini playbooks/site.yml -t common
```

### Check Current Settings
```bash
# SSH config
ssh <user>@<tailscale-hostname> "grep -E '^(Password|Permit|Max|Client|X11)' /etc/ssh/sshd_config"

# fail2ban status
ssh <user>@<tailscale-hostname> "sudo fail2ban-client status sshd"

# UFW rules
ssh <user>@<tailscale-hostname> "sudo ufw status verbose"

# sysctl values
ssh <user>@<tailscale-hostname> "sysctl kernel.randomize_va_space net.ipv4.tcp_syncookies"

# Tailscale status
ssh <user>@<tailscale-hostname> "tailscale status"
```
