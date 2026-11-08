#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL must be configured}"

HOME="${HOME:-/home/bun}"

# GBRAIN_HOME is the PARENT of the brain state directory, not the state
# directory itself: gbrain always appends "/.gbrain" (src/core/config.ts,
# configDir()). With GBRAIN_HOME=/home/bun/.gbrain the brain home is
# /home/bun/.gbrain/.gbrain, which is where the gbrain-home volume is mounted
# in compose.yaml. Keep the two in sync if the mount ever moves.
GBRAIN_HOME="${GBRAIN_HOME:-$HOME/.gbrain}"
CONFIG_DIR="$GBRAIN_HOME/.gbrain"
export HOME GBRAIN_HOME

log() {
    printf '[gbrain-entrypoint] %s\n' "$*" >&2
}

log "HOME=$HOME GBRAIN_HOME=$GBRAIN_HOME config_dir=$CONFIG_DIR"

# A fresh Docker volume is created root-owned; hand it to the unprivileged
# runtime user, and make sure the nested state directory exists and is
# writable before either service runs.
mkdir -p "$GBRAIN_HOME"
chown bun:bun "$GBRAIN_HOME"
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    chown bun:bun "$CONFIG_DIR"
fi

# Server and worker share this volume and start together. The file lock
# serializes them here; initSchema additionally takes a Postgres advisory
# lock (pg_advisory_lock(42)) so concurrent runs are safe even without it.
if [ -s "$CONFIG_DIR/config.json" ]; then
    # Existing brain: bring the schema to head and never re-run init.
    # `init --migrate-only` applies only pending migrations against the
    # already-configured engine and explicitly never rewrites config
    # (it is the documented orchestrator path). It is a no-op at head.
    log "existing brain config found; applying pending schema migrations (idempotent)"
    if ! gosu bun flock -x "$CONFIG_DIR/init.lock" \
        bun run /opt/gbrain/src/cli.ts init --migrate-only; then
        log "ERROR: schema migration failed; refusing to start so the failure is visible."
        log "       Diagnose with 'gbrain doctor --json' in this container and check DATABASE_URL."
        exit 1
    fi
else
    # Fresh brain: full, non-interactive initialization exactly once.
    log "no brain config found; initializing a new database-only brain"
    if ! gosu bun flock -x "$CONFIG_DIR/init.lock" \
        bun run /opt/gbrain/src/cli.ts init \
            --url "$DATABASE_URL" \
            --non-interactive \
            --no-embedding \
            --db-only; then
        log "ERROR: initial database setup failed; refusing to start."
        log "       If this database already holds a canonical content root, adopt it with"
        log "       'gbrain init --url \"\$DATABASE_URL\" --non-interactive --no-embedding'"
        log "       instead of --db-only, then restart."
        exit 1
    fi
    if [ ! -s "$CONFIG_DIR/config.json" ]; then
        log "ERROR: init reported success but $CONFIG_DIR/config.json is missing."
        exit 1
    fi
fi

log "starting: $*"
exec gosu bun bun run /opt/gbrain/src/cli.ts "$@"
