# Wren MCP block in /opt/caddy/Caddyfile on terracotta. Token = WREN_MCP_TOKEN in repo .env.
# EDIT IN PLACE (single-file bind mount): see CLAUDE.md "Caddy gotchas".
wren.kamisamanosumopod.my.id {
	import block_bots
	# 1) Header auth — Claude Code, Codex, mcp-remote
	@bearer header Authorization "Bearer __WREN_MCP_TOKEN__"
	handle @bearer {
		reverse_proxy wren:8080 {
			header_up Host 127.0.0.1:8080
		}
	}
	# 2) Path auth — clients that cannot send custom headers (ChatGPT, Claude Desktop connectors)
	#    https://wren.kamisamanosumopod.my.id/t/<token>/mcp  ->  wren:8080/mcp
	handle_path /t/__WREN_MCP_TOKEN__/* {
		reverse_proxy wren:8080 {
			header_up Host 127.0.0.1:8080
		}
	}
	respond 401
}
