#!/bin/sh
# Idempotent: profile add overwrites silently; init only if project missing.
set -e
wren profile add sidora --from-file /opt/wren/connection.yml --activate
cd /project
[ -f wren_project.yml ] || wren context init --empty
wren context set-profile sidora
wren context build
exec wren serve mcp --transport http --host 0.0.0.0 --port 8080 --project /project --quiet
