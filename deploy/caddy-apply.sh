#!/bin/sh
# Render deploy/Caddyfile.wren with WREN_MCP_TOKEN and install it as the wren block on terracotta.
# Idempotent: replaces an existing block or appends a new one. Writes BOTH the host file and the
# container's copy (single-file bind mount inode trap, see CLAUDE.md), validates, reloads, smoke-tests.
set -e
cd "$(dirname "$0")/.."
. ./.env
[ -n "$WREN_MCP_TOKEN" ] || { echo "WREN_MCP_TOKEN missing in .env"; exit 1; }
sed "s/__WREN_MCP_TOKEN__/$WREN_MCP_TOKEN/g" deploy/Caddyfile.wren | ssh terracotta 'set -e
NEW=$(cat)
cp /opt/caddy/Caddyfile "/opt/caddy/Caddyfile.bak-$(date +%F-%H%M)"
python3 - "$NEW" <<PY
import sys
p="/opt/caddy/Caddyfile"; s=open(p).read()
i=s.find("# Wren MCP block")
s=(s[:i].rstrip()+"\n\n" if i!=-1 else s.rstrip()+"\n\n")+sys.argv[1].rstrip()+"\n"
open(p,"w").write(s)
PY
docker exec -i caddy-caddy-1 sh -c "cat > /etc/caddy/Caddyfile" < /opt/caddy/Caddyfile
docker exec -w /etc/caddy caddy-caddy-1 caddy validate >/dev/null 2>&1 && echo "Caddyfile valid"
docker exec -w /etc/caddy caddy-caddy-1 caddy reload >/dev/null 2>&1 && echo "Caddy reloaded"'
sleep 2
B='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"caddy-apply","version":"0"}}}'
H='https://wren.kamisamanosumopod.my.id'
c() { curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d "$B" "$@"; }
echo "no auth      -> $(c $H/mcp) (want 401)"
echo "header auth  -> $(c $H/mcp -H "Authorization: Bearer $WREN_MCP_TOKEN") (want 200)"
echo "path auth    -> $(c $H/t/$WREN_MCP_TOKEN/mcp) (want 200)"
echo "wrong path   -> $(c $H/t/wrong/mcp) (want 401)"
