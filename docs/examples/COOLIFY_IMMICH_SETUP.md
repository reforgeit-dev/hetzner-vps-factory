# Coolify & Immich Setup

> **Example from a real deployment.** Replace all placeholder values with your own configuration.

Manual setup guide for the immich VPS profile. Coolify and Immich are installed manually (not via Ansible).

## Current State

| Component | Access | URL |
|-----------|--------|-----|
| Coolify | Tailscale only | `http://<tailscale-hostname>:8000` |
| Immich | Tailscale only | `https://immich.example.com` |
| Traefik dashboard | localhost only | `http://localhost:8080` |

All services accessible only via Tailscale. Hetzner Cloud firewall blocks all public access except Tailscale UDP.

## Architecture

```
Tailscale device (100.x.x.x)
    │
    ▼
Traefik (coolify-proxy, traefik:v3.6)
    ├── :80  → redirect to HTTPS
    ├── :443 → SSL termination (Let's Encrypt via Cloudflare DNS challenge)
    └── :8080 → Traefik API (not exposed publicly)
    │
    ├── immich.example.com → immich-server:2283
    │
    └── Coolify (:8000, separate port mapping, not via Traefik)

Immich stack (Coolify service <service-id>):
    ├── immich-server (ghcr.io/immich-app/immich-server:release)
    ├── immich-machine-learning (ghcr.io/immich-app/immich-machine-learning:release)
    ├── database (ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0)
    └── redis (redis:7.4-alpine)

Coolify platform:
    ├── coolify (ghcr.io/coollabsio/coolify:latest, :8000→8080)
    ├── coolify-db (postgres:15-alpine)
    ├── coolify-redis
    ├── coolify-realtime (:6001-6002)
    └── coolify-sentinel (metrics)
```

## File Layout on Server

```
/data/coolify/
├── proxy/
│   ├── docker-compose.yml          # Traefik proxy config
│   ├── acme.json                   # Let's Encrypt certificates
│   └── dynamic/
│       ├── Caddyfile               # Unused (Traefik is the active proxy)
│       └── default_redirect_503.yaml
├── services/
│   └── <service-id>/              # Immich service
│       ├── docker-compose.yml      # Immich stack definition
│       └── .env                    # Service credentials
├── backups/
│   └── coolify/coolify-db-*/       # Coolify's own DB backups (daily pg_dump)
├── sentinel/
│   └── metrics.sqlite              # Coolify metrics
├── ssl/
│   └── coolify-ca.crt
├── ssh/                            # Coolify SSH keys + mux sockets
├── applications/                   # Empty (no app deployments)
├── databases/                      # Empty (no standalone DBs)
└── source/                         # Empty
```

## Docker Volumes

| Volume | Location | Contents |
|--------|----------|----------|
| Immich uploads | **Storage Box** bind mount: `/mnt/storagebox/immich/uploads` | Photos, videos, thumbnails, backups |
| `<service-id>_immich-postgres-data` | Local Docker volume | PostgreSQL data |
| `<service-id>_immich-model-cache` | Local Docker volume | ML model cache (~786 MB) |
| `coolify-db` | Local Docker volume | Coolify's own PostgreSQL |
| `coolify-redis` | Local Docker volume | Coolify's Redis |

Immich uploads (media, thumbnails, encoded video, DB backups) are on the **1TB Storage Box** via SSHFS bind mount. PostgreSQL and ML cache stay on local SSD for performance.

## Storage Box

Mounted at `/mnt/storagebox` (1TB SSHFS via Ansible storagebox role, `allow_other` enabled for Docker access).

The Immich compose bind-mounts `/mnt/storagebox/immich/uploads:/usr/src/app/upload`. Immich's built-in daily DB backups (`.sql.gz`) also land here under `uploads/backups/`.

### Storagebox contents

```
/mnt/storagebox/immich/uploads/
├── backups/          # Immich's auto pg_dump (.sql.gz, daily)
├── encoded-video/    # Transcoded video
├── library/          # External library imports
├── profile/          # User profile photos
├── thumbs/           # Preview + thumbnail images
└── upload/           # Original uploaded files
```

## Docker Networks

| Network | Purpose |
|---------|---------|
| `coolify` | Coolify platform + Traefik proxy |
| `<service-id>` | Immich service (all 4 containers + connected to Traefik) |

## SSL / Traefik

- **Proxy**: Traefik v3.6 managed by Coolify
- **Certificate resolver**: Let's Encrypt via Cloudflare DNS challenge
- **Cloudflare API token**: stored in Traefik's environment (`CF_DNS_API_TOKEN`)
- **Certificate storage**: `/data/coolify/proxy/acme.json`
- **HTTP/3**: enabled on port 443/udp
- **DNS record**: `immich.example.com` → `<tailscale-ip>` (Tailscale IP only, Cloudflare DNS)

Since the domain points to a Tailscale IP, HTTP challenge won't work. DNS challenge is required.

## Immich Service Details

**Coolify service ID**: `<service-id>`

### Container Names

| Container | Image |
|-----------|-------|
| `immich-<service-id>` | `ghcr.io/immich-app/immich-server:release` |
| `immich-machine-learning-<service-id>` | `ghcr.io/immich-app/immich-machine-learning:release` |
| `database-<service-id>` | `ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0` |
| `redis-<service-id>` | `redis:7.4-alpine` |

### Database

- **Image**: Immich's custom Postgres 14 with vectorchord + pgvectors extensions
- **Database name**: `immich`
- **Credentials**: auto-generated by Coolify, stored in `.env`
- **Health check**: `pg_isready` every 5s
- **Data checksums**: enabled (`--data-checksums`)
- **No automated backups** of Immich's Postgres (Coolify only backs up its own DB)

---

## Installation Steps (for reference)

### 1. Install Coolify

```bash
ssh <user>@<tailscale-hostname>
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

Then access `http://<tailscale-hostname>:8000` and create admin account.

### 2. Configure SSL (Cloudflare DNS challenge)

In Coolify Settings:
- Set Traefik proxy as the default
- Add Cloudflare DNS API token for Let's Encrypt DNS challenge

### 3. Deploy Immich

1. Coolify dashboard → **Services** → **Add Service** → Search **Immich**
2. Set domain: `immich.example.com`
3. Enable SSL (Let's Encrypt)
4. Deploy

### 4. Configure DNS

In Cloudflare: `immich.example.com` → A record → `<tailscale-ip>`

---

## Verification

```bash
# All containers healthy
ssh <user>@<tailscale-hostname> "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(coolify|immich|redis|database)'"

# Immich responding
curl -I https://immich.example.com  # from Tailscale device

# Coolify dashboard
curl -I http://<tailscale-hostname>:8000

# Traefik logs
ssh <user>@<tailscale-hostname> "sudo docker logs coolify-proxy --tail 20"

# Immich server logs
ssh <user>@<tailscale-hostname> "sudo docker logs immich-<service-id> --tail 20"
```

## Maintenance

### Coolify Updates

Coolify self-updates via the dashboard (Settings → Update).

### Immich Updates

In Coolify dashboard → Immich service → **Redeploy** to pull latest `release` tag.

### Manual Postgres Backup

```bash
# Dump Immich database
ssh <user>@<tailscale-hostname> "sudo docker exec database-<service-id> pg_dump -U \$(sudo docker exec database-<service-id> printenv POSTGRES_USER) immich" > immich_backup_$(date +%Y%m%d).sql
```

### Coolify's Own Backups

Coolify auto-backs up its own Postgres database daily to `/data/coolify/backups/coolify/`. These are **not** Immich backups.

---

## Troubleshooting

### Coolify Not Accessible

```bash
ssh <user>@<tailscale-hostname> "sudo docker ps | grep coolify"
ssh <user>@<tailscale-hostname> "sudo docker logs coolify --tail 100"
```

### Immich Not Loading

```bash
ssh <user>@<tailscale-hostname> "sudo docker ps | grep -E 'immich|database|redis'"
ssh <user>@<tailscale-hostname> "sudo docker logs immich-<service-id> --tail 100"
```

### SSL Certificate Issues

```bash
ssh <user>@<tailscale-hostname> "sudo docker logs coolify-proxy --tail 100 2>&1 | grep -i acme"
```

### Restart Everything

```bash
# Restart just Immich (via Coolify compose)
ssh <user>@<tailscale-hostname> "cd /data/coolify/services/<service-id> && sudo docker compose up -d"

# Restart Traefik
ssh <user>@<tailscale-hostname> "cd /data/coolify/proxy && sudo docker compose restart"
```
