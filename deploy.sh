#!/bin/sh
# Deploy Wren MCP stack + wren-project to terracotta:/opt/wren and (re)start it.
# Secrets come from ./.env (never committed). Usage: ./deploy.sh [--no-build]
set -e
cd "$(dirname "$0")"
. ./.env
rsync -az --delete deploy/ terracotta:/opt/wren/ --exclude Caddyfile.wren
rsync -az --delete --exclude target/ wren-project/ terracotta:/opt/wren/project/
ssh terracotta 'umask 077; cat > /opt/wren/.env' <<ENV
POSTGRES_HOST=aws-1-ap-northeast-1.pooler.supabase.com
POSTGRES_PORT=5432
POSTGRES_DATABASE=postgres
POSTGRES_USER=postgres.wmkkjlxxiphgcynfgsjn
POSTGRES_PASSWORD=$SUPABASE_DB_PASSWORD
ENV
if [ "$1" = "--no-build" ]; then
  ssh terracotta 'cd /opt/wren && docker compose up -d'
else
  ssh terracotta 'cd /opt/wren && docker compose up -d --build'
fi
ssh terracotta 'cd /opt/wren && docker compose logs --tail 30 wren'
# Pull the compiled manifest back so the repo holds both source YAML and the served mdl.json.
sleep 5
rsync -az terracotta:/opt/wren/project/target/ wren-project/target/
echo "pulled wren-project/target/mdl.json ($(wc -c < wren-project/target/mdl.json) bytes)"
