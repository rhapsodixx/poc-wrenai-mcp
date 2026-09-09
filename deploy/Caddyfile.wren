# Appended to /opt/caddy/Caddyfile on terracotta. Token = WREN_MCP_TOKEN in repo .env.
wren.kamisamanosumopod.my.id {
	import block_bots
	@unauth not header Authorization "Bearer __WREN_MCP_TOKEN__"
	respond @unauth 401
	reverse_proxy wren:8080 {
		header_up Host 127.0.0.1:8080
	}
}
