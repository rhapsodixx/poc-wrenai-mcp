# Restore / redeploy runbook

Everything needed to rebuild the Wren MCP server is in this repo plus your local `.env`. The server holds
nothing unique: TLS certs are re-issued by Caddy, the Wren profile is recreated on container start, and the
compiled MDL is rebuilt from `wren-project/`.

## A. Server is alive, container or files broken (minutes)

```bash
./deploy.sh                 # rsync stack + project, write /opt/wren/.env, rebuild image, start, pull mdl.json back
./deploy/caddy-apply.sh     # (only if the Caddy block is missing/wrong) install block, reload, smoke-test 4 URLs
```

## B. Fresh server (Ubuntu 24.04), same domain

1. **DNS**: A record `wren` → new IP at ns1/ns2.sumopod.com (no wildcard exists). Update `terracotta_ip` in `.env`
   and the `Host terracotta` entry in `~/.ssh/config`; install your key: `ssh-copy-id root@<ip>`.
2. **Docker + shared network + swap** (run on the server):
   ```bash
   curl -fsSL https://get.docker.com | sh
   docker network create web
   fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile \
     && echo '/swapfile none swap sw 0 0' >> /etc/fstab
   mkdir -p /opt/caddy /opt/wren/project
   ```
3. **Caddy** (skip if the new server already runs the shared Caddy from another app):
   ```bash
   rsync -az deploy/caddy-base/ terracotta:/opt/caddy/
   ssh terracotta 'cd /opt/caddy && docker compose up -d'
   ```
4. **Wren**: `./deploy.sh` then `./deploy/caddy-apply.sh`. Expect `Built: 6 models` in the logs and
   `401 / 200 / 200 / 401` from the smoke test.
5. **Clients**: nothing changes if the domain and token are the same. Otherwise re-register per `README.md`.

## C. Lost the laptop too

- `.env` values: `SUPABASE_DB_PASSWORD` from the Supabase dashboard (or reset it there); `WREN_MCP_TOKEN` can simply
  be regenerated (`openssl rand -hex 32`) and clients re-registered. Keep a copy of `.env` in Vaultwarden.
- Everything else: `git clone` this repo, then B.

## Verify after any restore

```bash
ssh terracotta 'docker exec -w /project wren wren --sql "select count(*) from team_members"'   # DB reachable via MDL
./deploy/caddy-apply.sh                                                                          # 4-URL smoke test
claude mcp list                                                                                  # wren ✔ Connected
```

## Upgrading Wren

Edit the `wrenai==` line in `deploy/requirements.lock.txt` (keep `mcp<2` unless the changelog says FastMCP moved),
`./deploy.sh`, check logs, then re-freeze so the lock reflects reality:
`ssh terracotta 'docker exec wren pip freeze' > deploy/requirements.lock.txt`.
