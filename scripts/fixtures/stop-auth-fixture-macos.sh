#!/usr/bin/env bash

set -euo pipefail

if [[ -z ${AUTH_FIXTURE_RUNTIME_DIR:-} ]]; then
    echo "Required environment variable is not set: AUTH_FIXTURE_RUNTIME_DIR" >&2
    exit 2
fi

postgres_bin=${AUTH_POSTGRES_BIN:-$(brew --prefix postgresql@15)/bin}
museum_pid_file="$AUTH_FIXTURE_RUNTIME_DIR/museum.pid"
postgres_data="$AUTH_FIXTURE_RUNTIME_DIR/postgres"

if [[ -f "$museum_pid_file" ]]; then
    museum_pid=$(cat "$museum_pid_file")
    if [[ "$museum_pid" =~ ^[0-9]+$ ]] && kill -0 "$museum_pid" 2>/dev/null; then
        kill "$museum_pid"
        for _ in {1..30}; do
            if ! kill -0 "$museum_pid" 2>/dev/null; then
                break
            fi
            sleep 1
        done
    fi
fi

if [[ -f "$postgres_data/postmaster.pid" ]]; then
    "$postgres_bin/pg_ctl" --pgdata="$postgres_data" --mode=fast --wait stop >/dev/null
fi
