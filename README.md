# Wren AI MCP — ask `sidora` in plain language from your AI client

A self-hosted [Wren AI](https://docs.getwren.ai/oss) semantic layer running on **terracotta**, exposed as a
remote **MCP server**. Point Claude Code, Codex, Claude Desktop, or ChatGPT at it and ask business questions;
the agent gets the schema and business rules from Wren, writes SQL against the semantic model, and runs it.

| | |
|---|---|
| Endpoint | `https://wren.kamisamanosumopod.my.id/mcp` (Streamable HTTP) |
| Auth | Bearer token (`WREN_MCP_TOKEN` in `.env`, ask Panji). Header **or** path form, see below |
| Mode | Read-only. Row limit 1000 per query |
| Connected databases | see [Connected databases](#connected-databases) |

Two URL forms, same token:

| Form | URL | Use with |
|---|---|---|
| Header | `https://wren.kamisamanosumopod.my.id/mcp` + `Authorization: Bearer <token>` | Claude Code, Codex, `mcp-remote` |
| Path | `https://wren.kamisamanosumopod.my.id/t/<token>/mcp` | Clients that cannot send custom headers: ChatGPT, Claude Desktop connector |

The path form exists because ChatGPT and the Claude Desktop "custom connector" only support OAuth or no auth.
Treat that URL like a password (it lands in URL logs). Rotate the token if it leaks (see CLAUDE.md).

---

## Claude Code

```bash
claude mcp add --transport http wren https://wren.kamisamanosumopod.my.id/mcp \
  --header "Authorization: Bearer <token>"
claude mcp list          # wren: … ✔ Connected
```

Then in a session: *"Using the wren tools, which group merged the most MRs last quarter?"*
Add `-s user` to make it available in every project instead of only this one.

## Codex (CLI and desktop app share `~/.codex/config.toml`)

```bash
export WREN_MCP_TOKEN=<token>      # put it in your shell profile
codex mcp add wren --url https://wren.kamisamanosumopod.my.id/mcp --bearer-token-env-var WREN_MCP_TOKEN
codex mcp list
```

Equivalent `~/.codex/config.toml`:

```toml
[mcp_servers.wren]
url = "https://wren.kamisamanosumopod.my.id/mcp"
bearer_token_env_var = "WREN_MCP_TOKEN"
```

## Claude Desktop

Two options.

**A. Custom connector (no local install).** Settings → Connectors → **Add custom connector** → paste the **path form** URL
`https://wren.kamisamanosumopod.my.id/t/<token>/mcp`, leave OAuth fields empty. Free plan allows one custom connector.

**B. `mcp-remote` bridge (keeps the token out of the URL).** Edit
`~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) and restart Claude Desktop:

```json
{
  "mcpServers": {
    "wren": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://wren.kamisamanosumopod.my.id/mcp",
               "--header", "Authorization:${AUTH_HEADER}", "--transport", "http-only"],
      "env": { "AUTH_HEADER": "Bearer <token>" }
    }
  }
}
```

Note `Authorization:${AUTH_HEADER}` has no space after the colon; the space lives in the env var on purpose
(Claude Desktop mangles spaces inside `args`). Requires Node.js.

## ChatGPT (desktop and web, Plus/Pro/Business/Enterprise/Edu)

1. Settings → **Apps & Connectors** (older builds: **Security and login**) → enable **Developer mode**.
2. Connectors → **Create** → name `wren`, URL `https://wren.kamisamanosumopod.my.id/t/<token>/mcp`,
   Authentication **No authentication** → Create.
3. In a chat, open the **+** / tools menu, enable the `wren` connector, then ask. Developer mode exposes all
   tools; `search`/`fetch` are not required.

---

## How the agent should work with Wren

Every client sees the same tools. A good session usually goes:

1. `get_instructions` for business rules, then `describe_schema` or `list_models` to learn the model.
2. `dry_run` the SQL, fix errors from the structured hints, then `run_sql`.
3. Write SQL against **model names** (`team_members`, `mr_snapshots`, …), not raw table names.

Tools: `run_sql`, `dry_run`, `dry_plan`, `query_cube`, `get_mdl`, `list_models`, `describe_model`, `describe_schema`,
`get_data_source`, `list_cubes`, `describe_cube`, `list_functions`, `get_instructions`, `recall_queries`, `get_context`,
`list_stored_queries`, `list_knowledge`. Resources: `wren://mdl`, `wren://instructions`, `wren://project`.

## Connected databases

| Connection | Source | Knowledge file |
|---|---|---|
| `sidora` | Supabase project `wmkkjlxxiphgcynfgsjn` (Tokyo), schema `public`, engineering-productivity data | [knowledge-sidora.md](knowledge-sidora.md) |

Each knowledge file explains the models (MDL), their relationships, and prompts you can try. When a new
connection is added, add a row here and a `knowledge-<connection>.md` next to it.

## Repo

Operations, server layout, deploy, and MDL editing loop: see [CLAUDE.md](CLAUDE.md). The MDL itself lives in
[`wren-project/`](wren-project/).
