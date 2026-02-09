# Coolify & Immich Setup

> **Example from a real deployment.** Replace all placeholder values with your own configuration.

Manual setup guide for the immich VPS profile. Coolify is installed via Ansible (`install_coolify: true`), but the admin account, SSL configuration, and Immich deployment are done manually through the Coolify UI.

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
└── source/                         # Coolify compose + .env
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
├── .immich               # Mount integrity marker (created by Immich)
├── backups/              # Immich's auto pg_dump (.sql.gz, daily)
├── encoded-video/        # Transcoded video
├── library/              # External library imports
├── profile/              # User profile photos
├── thumbs/               # Preview + thumbnail images
└── upload/               # Original uploaded files
```

### Storagebox preparation

Before deploying Immich with storagebox storage, create the required subdirectories:

```bash
sudo mkdir -p /mnt/storagebox/immich/uploads/{encoded-video,library,profile,thumbs,upload,backups}
```

Immich creates `.immich` marker files in each subdirectory on first startup for mount integrity verification.

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

## Installation Steps

### Prerequisites (Ansible)

The following must be completed via Ansible before starting:

1. **Docker** installed (`install_docker: true`)
2. **Tailscale** connected (`install_tailscale: true`)
3. **Storage Box** mounted with `allow_other` (`storagebox_directories: [immich]`)
4. **Coolify** installed (`install_coolify: true`)
5. **Root SSH enabled** (`disable_root_ssh: false`) — Coolify SSHs to localhost from inside Docker
6. **fail2ban** must whitelist Docker subnets (`172.16.0.0/12` in `ignoreip`) — otherwise Coolify's SSH attempts during setup trigger a ban
7. **DNS** configured: `immich.example.com` → A record → `<tailscale-ip>` (Cloudflare)

### 1. Create Coolify Admin Account

Access `http://<tailscale-hostname>:8000` and create the admin account.

### 2. Complete Server Setup Wizard

1. Choose **"Deploy on this server"** (localhost)
2. The SSH key was pre-generated by Ansible — the wizard validates connectivity using it
3. If SSH validation fails with "Server is not reachable", check that fail2ban hasn't banned the Coolify container IP (see Troubleshooting)

### 3. Configure SSL (Cloudflare DNS Challenge)

Traefik defaults to HTTP challenge, which won't work with Tailscale IPs. Switch to DNS challenge:

1. In Coolify, go to **Servers** → your server → **Proxy** tab → **Dynamic Configuration** (or edit the Traefik docker-compose)
2. Add to `environment` section:
   ```yaml
   - CF_DNS_API_TOKEN=<your-cloudflare-api-token>
   ```
3. In `command` section, replace:
   ```yaml
   - '--certificatesresolvers.letsencrypt.acme.httpchallenge=true'
   - '--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http'
   ```
   with:
   ```yaml
   - '--certificatesResolvers.letsencrypt.acme.dnsChallenge=true'
   - '--certificatesResolvers.letsencrypt.acme.dnsChallenge.provider=cloudflare'
   ```
4. Save — Coolify recreates the Traefik container automatically (important: a plain `docker compose restart` would NOT pick up command changes — the container must be recreated)

The Cloudflare API token needs **Zone:DNS:Edit** permission for the domain.

### 4. Prepare Storage Box Directories

```bash
sudo mkdir -p /mnt/storagebox/immich/uploads/{encoded-video,library,profile,thumbs,upload,backups}
```

### 5. Deploy Immich

1. Coolify dashboard → **Projects** → **Add** → **Add Resources** → **Services** → search **Immich**
2. Set the Immich service URL to `https://immich.example.com:2283` — both `https://` and the internal port `:2283` are required in the Coolify service URL field
3. Change the uploads volume from Docker volume to storagebox bind mount:
   - Volume mounts are **read-only** in the Coolify dashboard for compose-based services — edit your **Docker Compose file** in Coolify and reload
   - In the `immich-server` service volumes, replace the named volume with a bind mount:
     ```yaml
     - /mnt/storagebox/immich/uploads:/usr/src/app/upload
     ```
4. Click **Deploy**
5. Wait for all 4 containers to show **Running (healthy)** — first deploy downloads ~2GB of images

### 6. Verify

```bash
# All containers healthy
ssh <user>@<tailscale-hostname> "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(coolify|immich|redis|database)'"

# SSL working
curl -I https://immich.example.com  # from Tailscale device

# Storage Box mounted correctly
ssh <user>@<tailscale-hostname> "sudo docker inspect immich-<service-id> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'"
```

Access `https://immich.example.com` and create your Immich user account.

---

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

### Migrate Immich Data to Storage Box

If Immich was initially deployed with a Docker volume and you need to move data to the storagebox:

```bash
# 1. Stop Immich
cd /data/coolify/services/<service-id> && sudo docker compose down

# 2. Find the Docker volume mount point
sudo docker volume inspect <service-id>_immich-uploads --format '{{.Mountpoint}}'

# 3. Rsync to storagebox (--no-owner --no-group because SSHFS doesn't support chown)
sudo rsync -av --no-owner --no-group /var/lib/docker/volumes/<service-id>_immich-uploads/_data/ /mnt/storagebox/immich/uploads/

# 4. Update the compose volume to bind mount (see Step 5 above), then restart
cd /data/coolify/services/<service-id> && sudo docker compose up -d
```

### Coolify's Own Backups

Coolify auto-backs up its own Postgres database daily to `/data/coolify/backups/coolify/`. These are **not** Immich backups.

---

## Troubleshooting

### Coolify Setup: "Server is not reachable"

Coolify SSHs to the host from inside a Docker container. If fail2ban bans the container IP:

```bash
# Check if container IP is banned
sudo fail2ban-client status sshd

# Unban (container IP varies, check with docker inspect)
sudo fail2ban-client set sshd unbanip <container-ip>

# Permanent fix: add Docker subnets to fail2ban ignoreip
# In /etc/fail2ban/jail.local, add 172.16.0.0/12 to ignoreip
# Or set in Ansible: fail2ban_ignoreip includes 172.16.0.0/12
```

### Coolify Onboarding: "getPublicKey() on null"

The onboarding wizard expects the SSH key at `/data/coolify/ssh/keys/id.root@host.docker.internal` to already exist. If the Ansible coolify role didn't generate it (or it was deleted), the wizard crashes with a 500 error. Fix: re-run the Ansible coolify role, then restart Coolify containers.

### Coolify Not Accessible

```bash
ssh <user>@<tailscale-hostname> "sudo docker ps | grep coolify"
ssh <user>@<tailscale-hostname> "sudo docker logs coolify --tail 100"
```

### Immich Not Loading / Crash Loop

If Immich fails with mount integrity errors (`Failed to read .immich`):

```bash
# Ensure storagebox subdirectories exist
sudo mkdir -p /mnt/storagebox/immich/uploads/{encoded-video,library,profile,thumbs,upload,backups}

# Restart Immich
sudo docker restart immich-<service-id>
```

### SSL Certificate Issues

```bash
# Check Traefik ACME logs
ssh <user>@<tailscale-hostname> "sudo docker logs coolify-proxy --tail 100 2>&1 | grep -i acme"

# Verify DNS challenge is configured (not HTTP challenge)
ssh <user>@<tailscale-hostname> "sudo docker inspect coolify-proxy --format '{{.Args}}'" | tr ',' '\n' | grep -i challenge
```

### Restart Everything

```bash
# Restart just Immich (via Coolify compose)
ssh <user>@<tailscale-hostname> "cd /data/coolify/services/<service-id> && sudo docker compose up -d"

# Restart Traefik
ssh <user>@<tailscale-hostname> "cd /data/coolify/proxy && sudo docker compose restart"
```
