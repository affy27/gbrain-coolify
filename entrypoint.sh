#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL must be configured}"

mkdir -p "$HOME/.gbrain"
chown bun:bun "$HOME/.gbrain"

gosu bun flock -x "$HOME/.gbrain/init.lock" sh -c '
    if [ ! -s "$HOME/.gbrain/config.json" ]; then
        echo "First startup: initializing GBrain PostgreSQL database..."
        bun run /opt/gbrain/src/cli.ts init \
            --url "$DATABASE_URL" \
            --non-interactive \
            --no-embedding \
            --db-only
    else
        echo "Existing GBrain configuration found; skipping initialization."
    fi
'

exec gosu bun bun run /opt/gbrain/src/cli.ts "$@"
