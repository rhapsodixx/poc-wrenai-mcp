# poc-wrenai — Wren AI MCP server on terracotta, backed by Supabase "sidora"

Proof of concept: self-hosted **Wren AI OSS** (semantic layer + governed text-to-SQL) exposed as an
**MCP server** so AI agents (Claude Code, Cursor, …) can query the Supabase database `sidora`.
This repo is the **source of truth** for the Wren project (MDL, knowledge, rules) and the deploy stack.

## Which Wren AI this is (important, product split May 2026)

| | Chosen: **Wren AI OSS `main`** | Not chosen: Wren GenBI Classic (`legacy/v1`) |
|---|---|---|
| Form | pip CLI `wrenai` + `wren serve mcp` | 6-container Docker chat web UI |
| Footprint | ~70 MB RAM idle, one container | ~3–4 GB RAM, needs OpenAI key server-side |
| Status | Active | Sunset, no security fixes; web UI is now commercial-only |

The LLM lives on the **agent side** (your Claude Code). The server only does schema/MDL planning and SQL execution.
Docs: https://docs.getwren.ai/oss · Repo: https://github.com/Canner/WrenAI (CLI source: `core/wren/`).

## Repo layout

```
CLAUDE.md
README.md               # how to connect Claude Code / Codex / Claude Desktop / ChatGPT
knowledge-sidora.md     # MDL explanation + sample prompts for the sidora connection (one file per connection)
.env                    # secrets, NEVER commit (see keys below)
deploy.sh               # rsync deploy/ + wren-project/ -> terracotta:/opt/wren, write server .env, compose up --build
deploy/
  Dockerfile            # python:3.12-slim + wrenai[postgres,mcp] + mcp<2 pin
  docker-compose.yml    # service `wren`, joins external network `web`, mem_limit 1.5g, no host ports
  entrypoint.sh         # profile add -> context init (if missing) -> set-profile -> build -> serve mcp :8080
  connection.yml        # postgres profile, values from ${POSTGRES_*} env
  Caddyfile.wren        # reference copy of the block appended to /opt/caddy/Caddyfile (token placeholder)
scripts/
  generate_models.py    # regenerate models/*/metadata.yml + relationships.yml from live schema (preserves descriptions)
wren-project/           # THE Wren project (schema_version 5). Add MDL here.
  wren_project.yml      # catalog: wren, schema: public (Wren namespace, NOT the DB schema), profile: sidora
  models/<table>/metadata.yml
  relationships.yml
  views/  cubes/        # add named SQL views / pre-aggregation cubes here
  knowledge/rules|glossary|metrics|caveats|sql
  target/               # build output (gitignored, built inside the container)
```

`.env` keys: `terracotta_ip|username|password` (SSH fallback; key auth is installed), `SUPABASE_DB_PASSWORD`,
`SUPABASE_DB_HOST/USER` (direct host, informational), `WREN_MCP_TOKEN` (bearer token enforced by Caddy).

## Target server: terracotta (sumopod.com VPS)

- `ssh terracotta` (alias in `~/.ssh/config` → root@103.92.215.36, key auth). Hostname `sumopod-9f95…`.
- Ubuntu 24.04, 4 vCPU Xeon, 7.8 GB RAM (+2 GB swapfile added 2026-09-09), 58 GB disk (~31 GB free), no IPv6, ufw inactive.
- Docker 29 / Compose v5. **Convention:** one compose project per app in `/opt/<app>/`, containers join the
  external bridge network `web`, no host ports; Caddy (`caddy-caddy-1`, `/opt/caddy`) terminates TLS and
  reverse-proxies by container name. Other tenants: multica, hindsight, hermes-gojo/rin, omniroute, openclaw-isti,
  uptimekuma, vaultwarden, panjigautama-hugo. Baseline RAM use before Wren ≈ 5.5 GB.
- DNS for `*.kamisamanosumopod.my.id` is at ns1/ns2.sumopod.com, **no wildcard**: each subdomain is a manual A record.

### Caddy gotchas (learned the hard way)
- `/opt/caddy/Caddyfile` is a **single-file bind mount**. `sed -i` (and editors that replace the file) create a new
  inode the container never sees. A `sed -i` already happened on 2026-09-09, so until Caddy is next recreated the
  container's copy is a separate inode: after editing the host file, also sync it into the container:
  `docker exec -i caddy-caddy-1 sh -c 'cat > /etc/caddy/Caddyfile' < /opt/caddy/Caddyfile` (then validate + reload).
  Recreating the caddy container (`docker compose up -d --force-recreate` in /opt/caddy) re-binds to the host file
  but briefly drops every site.
- Reload without restarting (other sites stay up):
  `docker exec -w /etc/caddy caddy-caddy-1 caddy validate && docker exec -w /etc/caddy caddy-caddy-1 caddy reload`
- Backups live next to it as `Caddyfile.bak-YYYY-MM-DD`.

### Wren block in Caddy
`wren.kamisamanosumopod.my.id` → `import block_bots`, then two authenticated routes, else 401:
1. `Authorization: Bearer $WREN_MCP_TOKEN` → `reverse_proxy wren:8080` (Claude Code, Codex, mcp-remote).
2. `handle_path /t/$WREN_MCP_TOKEN/*` → same upstream, prefix stripped (ChatGPT and Claude Desktop custom connectors,
   which only support OAuth or no-auth, so the token rides in the URL).
Both routes set `header_up Host 127.0.0.1:8080`. That rewrite is required: the MCP Python SDK enables DNS-rebinding
protection at `FastMCP()` construction with allowlist `127.0.0.1:* | localhost:* | [::1]:*` and `wren` offers no flag
to change it; anything else returns `421 Invalid Host header`. Reference copy: `deploy/Caddyfile.wren`.
Client setup docs: `README.md`. Per-connection MDL docs: `knowledge-<connection>.md`.

## Supabase "sidora"

- Project ref `wmkkjlxxiphgcynfgsjn`, URL https://wmkkjlxxiphgcynfgsjn.supabase.co, region **ap-northeast-1 (Tokyo)**.
- Direct host `db.wmkkjlxxiphgcynfgsjn.supabase.co` is **IPv6-only** → unreachable from terracotta. Use the Supavisor
  pooler, **session mode**: `aws-1-ap-northeast-1.pooler.supabase.com:5432`, user `postgres.wmkkjlxxiphgcynfgsjn`,
  db `postgres`, `sslmode=require`. (Region was found by probing poolers: wrong region says "tenant/user not found".)
- Schema `public` (6 tables, engineering-productivity data): `groups`, `team_members` (FK group_id→groups),
  `mr_snapshots` (monthly GitLab MR metrics per member, FK→team_members), `cc_snapshots` (monthly Claude Code
  lines_adopted per member, FK→team_members), `gitlab_groups`, `users` (app users, auth_id→Supabase auth).
- Currently connecting as `postgres` (superuser). TODO before anything beyond POC: create a read-only role.

## Runbook

```bash
./deploy.sh                 # full deploy (rebuild image); ./deploy.sh --no-build to just sync + restart
ssh terracotta 'cd /opt/wren && docker compose logs -f wren'
ssh terracotta 'cd /opt/wren && docker compose restart wren'      # reload MDL after a build
ssh terracotta 'docker exec -w /project wren wren --sql "select count(*) from team_members"'
ssh terracotta 'docker exec wren wren context validate --path /project'
ssh terracotta 'docker exec wren wren profile debug'
```

MCP client (Claude Code, local scope):
```bash
claude mcp add --transport http wren https://wren.kamisamanosumopod.my.id/mcp \
  --header "Authorization: Bearer $WREN_MCP_TOKEN"
```
Smoke test: POST a JSON-RPC `initialize` body to `/mcp` → 401 without auth, 200 `text/event-stream` with the bearer
header, 200 via `/t/$WREN_MCP_TOKEN/mcp`, 401 via `/t/wrong/mcp`.

## Editing the MDL (the normal loop)

1. Edit YAML under `wren-project/` (models, `relationships.yml`, `views/`, `cubes/`, `knowledge/`).
   Add `properties.description` to models/columns — validate warns when missing and agents answer better with them.
2. `./deploy.sh --no-build` → rsyncs the project, container restarts, `entrypoint.sh` runs `wren context build`.
   Build errors show in `docker compose logs wren`; the server keeps serving the last good `target/mdl.json`.
3. New tables in Supabase: `ssh terracotta 'docker exec -i wren python -' < scripts/generate_models.py`, then
   `rsync -az --exclude target/ terracotta:/opt/wren/project/ wren-project/` and review the diff.
   Existing descriptions are preserved; everything else is regenerated. Edit `SCHEMAS` in the script for more schemas.
4. `wren_project.yml` `catalog`/`schema` are Wren's namespace; keep `wren`/`public`. The DB schema is per-model `table_reference.schema`.

## Deliberate simplifications
- No `memory` extra (pulls PyTorch, +2 GB). Recall tools fall back to plain reads of `knowledge/`. Add `memory-onnx` if recall matters.
- MCP server is read-only (`store_query` disabled). Add `--allow-write` in `entrypoint.sh` to let agents save queries.
- `mcp<2` pin: wrenai 0.14.0 still imports `mcp.server.fastmcp` (removed in mcp 2.x). Drop the pin when wrenai upgrades.
- Auth is a single shared bearer token in Caddy, accepted as header or URL path segment. Rotate by editing `.env`, then
  the Caddyfile block on host **and** through the container (see gotcha), reload, and re-register every client.
