#!/usr/bin/env bash

set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
    echo "The native Auth fixture runner requires macOS" >&2
    exit 2
fi

for name in AUTH_FIXTURE_RUNTIME_DIR AUTH_MUSEUM_BINARY AUTH_MUSEUM_SOURCE_DIR; do
    if [[ -z ${!name:-} ]]; then
        echo "Required environment variable is not set: $name" >&2
        exit 2
    fi
done

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
manifest="$repo_root/museum/fixtures/manifest.json"
dump="$repo_root/museum/fixtures/auth-fixture-v2.dump"
museum_config="$repo_root/museum/museum.yaml"
postgres_port=${AUTH_POSTGRES_PORT:-5432}
museum_port=${AUTH_MUSEUM_PORT:-8080}
postgres_prefix=$(brew --prefix postgresql@15)
postgres_bin="$postgres_prefix/bin"
postgres_data="$AUTH_FIXTURE_RUNTIME_DIR/postgres"
museum_log="$AUTH_FIXTURE_RUNTIME_DIR/museum.log"
museum_pid_file="$AUTH_FIXTURE_RUNTIME_DIR/museum.pid"

"$repo_root/scripts/fixtures/verify-auth-fixture.sh"
expected_revision=$(jq --raw-output '.museumServerRevision' "$manifest")
actual_revision=$(git -C "$AUTH_MUSEUM_SOURCE_DIR" rev-parse HEAD)
if [[ "$actual_revision" != "$expected_revision" ]]; then
    echo "Museum checkout does not match the fixture server revision" >&2
    exit 1
fi
if [[ ! -x "$AUTH_MUSEUM_BINARY" ]]; then
    echo "Museum binary is not executable: $AUTH_MUSEUM_BINARY" >&2
    exit 1
fi

mkdir -p "$AUTH_FIXTURE_RUNTIME_DIR"

cleanup_on_error() {
    status=$?
    trap - EXIT
    if [[ $status -ne 0 ]]; then
        AUTH_POSTGRES_BIN="$postgres_bin" \
            "$repo_root/scripts/fixtures/stop-auth-fixture-macos.sh" || true
        if [[ -f "$museum_log" ]]; then
            tail -n 100 "$museum_log" >&2
        fi
    fi
    exit "$status"
}
trap cleanup_on_error EXIT

"$postgres_bin/initdb" \
    --pgdata="$postgres_data" \
    --auth=trust \
    --encoding=UTF8 \
    --no-locale \
    --username=ente_auth >/dev/null
"$postgres_bin/pg_ctl" \
    --pgdata="$postgres_data" \
    --options="-p $postgres_port -h 127.0.0.1" \
    --wait start >/dev/null
"$postgres_bin/createdb" \
    --host=127.0.0.1 \
    --port="$postgres_port" \
    --username=ente_auth \
    ente_auth_test
"$postgres_bin/pg_restore" \
    --host=127.0.0.1 \
    --port="$postgres_port" \
    --username=ente_auth \
    --dbname=ente_auth_test \
    --exit-on-error \
    --no-owner \
    --no-privileges < "$dump"

account_state=$(
    "$postgres_bin/psql" \
        --host=127.0.0.1 \
        --port="$postgres_port" \
        --tuples-only \
        --no-align \
        --field-separator='|' \
        --username=ente_auth \
        --dbname=ente_auth_test \
        --command="SELECT (SELECT COUNT(*) FROM users), (SELECT COUNT(*) FROM users WHERE source = 'authMaestroFixture'), (SELECT COUNT(*) FROM users WHERE is_two_factor_enabled), (SELECT COUNT(*) FROM authenticator_key), (SELECT COUNT(*) FROM authenticator_entity), (SELECT COUNT(*) FROM authenticator_entity WHERE is_deleted);"
)
if [[ "$account_state" != "3|3|1|3|5|0" ]]; then
    echo "Restored database does not contain the exact fixture-v2 state" >&2
    exit 1
fi

(
    cd "$AUTH_MUSEUM_SOURCE_DIR/server"
    exec env \
        ENTE_DB_HOST=127.0.0.1 \
        ENTE_DB_PORT="$postgres_port" \
        ENTE_DB_NAME=ente_auth_test \
        ENTE_DB_USER=ente_auth \
        ENTE_DB_PASSWORD=ente_auth \
        ENTE_DB_SSLMODE=disable \
        ENTE_HTTP_PORT="$museum_port" \
        ENTE_CREDENTIALS_FILE="$museum_config" \
        GIT_COMMIT="$expected_revision" \
        "$AUTH_MUSEUM_BINARY"
) > "$museum_log" 2>&1 &
echo "$!" > "$museum_pid_file"

for _ in {1..60}; do
    if curl --fail --silent "http://127.0.0.1:$museum_port/ping" | jq --exit-status \
        --arg revision "$expected_revision" \
        '.message == "pong" and .id == $revision' >/dev/null; then
        trap - EXIT
        echo "Restored Auth fixture v2 and started native Museum $expected_revision"
        if [[ -n ${GITHUB_ENV:-} ]]; then
            {
                echo "AUTH_FIXTURE_DB_MODE=native"
                echo "AUTH_POSTGRES_BIN=$postgres_bin"
                echo "AUTH_POSTGRES_PORT=$postgres_port"
            } >> "$GITHUB_ENV"
        fi
        exit 0
    fi
    sleep 1
done

exit 1
