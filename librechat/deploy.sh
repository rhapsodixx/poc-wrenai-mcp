#!/bin/sh
# Deploy LibreChat (api + mongo) to terracotta:/opt/librechat, install its Caddy block, (re)start.
# Secrets come from ../.env (never committed). Usage: librechat/deploy.sh
set -e
cd "$(dirname "$0")/.."
. ./.env
for k in WREN_MCP_TOKEN LIBRECHAT_JWT_SECRET LIBRECHAT_JWT_REFRESH_SECRET LIBRECHAT_CREDS_KEY LIBRECHAT_CREDS_IV; do
  eval "[ -n \"\$$k\" ]" || { echo "$k missing in .env"; exit 1; }
done
rsync -az librechat/docker-compose.yml librechat/librechat.yaml terracotta:/opt/librechat/
ssh terracotta 'umask 077; cat > /opt/librechat/.env' <<ENV
DOMAIN_CLIENT=https://librechat.kamisamanosumopod.my.id
DOMAIN_SERVER=https://librechat.kamisamanosumopod.my.id
TRUST_PROXY=1
NO_INDEX=true
SEARCH=false
ENDPOINTS=agents,anthropic
ANTHROPIC_API_KEY=user_provided
ALLOW_REGISTRATION=${LIBRECHAT_ALLOW_REGISTRATION:-true}
ALLOW_SOCIAL_LOGIN=false
JWT_SECRET=$LIBRECHAT_JWT_SECRET
JWT_REFRESH_SECRET=$LIBRECHAT_JWT_REFRESH_SECRET
CREDS_KEY=$LIBRECHAT_CREDS_KEY
CREDS_IV=$LIBRECHAT_CREDS_IV
WREN_MCP_TOKEN=$WREN_MCP_TOKEN
ENV
# Caddy block: write host file AND container copy (inode trap), validate, reload.
ssh terracotta 'set -e
NEW=$(cat)
cp /opt/caddy/Caddyfile "/opt/caddy/Caddyfile.bak-$(date +%F-%H%M)"
python3 - "$NEW" <<PY
import sys,re
p="/opt/caddy/Caddyfile"; s=open(p).read()
s=re.sub(r"\n*# LibreChat block.*?\n}\n", "\n", s, count=1, flags=re.S)
open(p,"w").write(s.rstrip()+"\n\n"+sys.argv[1].rstrip()+"\n")
PY
docker exec -i caddy-caddy-1 sh -c "cat > /etc/caddy/Caddyfile" < /opt/caddy/Caddyfile
docker exec -w /etc/caddy caddy-caddy-1 caddy validate >/dev/null 2>&1 && echo "Caddyfile valid"
docker exec -w /etc/caddy caddy-caddy-1 caddy reload >/dev/null 2>&1 && echo "Caddy reloaded"' < librechat/Caddyfile.librechat
ssh terracotta 'cd /opt/librechat && docker compose pull -q && docker compose up -d && sleep 15 && docker compose logs --tail 40 librechat'
H=https://librechat.kamisamanosumopod.my.id
echo "site       -> $(curl -s -m 15 -o /dev/null -w '%{http_code}' $H/) (want 200)"
echo "robots.txt -> $(curl -s -m 10 $H/robots.txt | tr '\n' ' ') (want Disallow: /)"
echo "X-Robots   -> $(curl -s -m 10 -I $H/ | grep -i x-robots-tag | tr -d '\r')"
