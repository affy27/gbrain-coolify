#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL must be configured}"

HOME="${HOME:-/home/bun}"
GBRAIN_HOME="${GBRAIN_HOME:-$HOME/.gbrain}"

export HOME GBRAIN_HOME

mkdir -p "$GBRAIN_HOME"
chown bun:bun "$GBRAIN_HOME"

# Initialize the shared database once, even if server and worker start together.
gosu bun flock -x "$GBRAIN_HOME/init.lock" sh -c '
    if [ ! -s "$GBRAIN_HOME/config.json" ]; then
        echo "Initializing GBrain PostgreSQL database..."
        bun run /opt/gbrain/src/cli.ts init \
            --url "$DATABASE_URL" \
            --non-interactive \
            --no-embedding \
            --db-only
    else
        echo "GBrain configuration already exists; skipping initialization."
    fi
'

exec gosu bun bun run /opt/gbrain/src/cli.ts "$@"
