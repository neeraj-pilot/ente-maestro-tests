#!/usr/bin/env bash

set -euo pipefail

if [[ ${ALLOW_AUTH_FIXTURE_RESTORE:-} != "1" ]]; then
    echo "Set ALLOW_AUTH_FIXTURE_RESTORE=1 to restore the public local Auth fixture" >&2
    exit 1
fi

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
compose_file="$repo_root/museum/compose.yaml"
dump="$repo_root/museum/fixtures/auth-fixture-v2.dump"
project=${AUTH_FIXTURE_COMPOSE_PROJECT:-ente-auth-fixture}
compose=(docker compose --project-name "$project" --file "$compose_file")

cleanup_on_error() {
    status=$?
    if [[ $status -ne 0 ]]; then
        "${compose[@]}" ps || true
        "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
    fi
    exit "$status"
}
trap cleanup_on_error EXIT

"$repo_root/scripts/fixtures/verify-auth-fixture.sh"
"${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
"${compose[@]}" up --detach postgres

for _ in {1..60}; do
    if "${compose[@]}" exec -T postgres \
        pg_isready --quiet --dbname=ente_auth_test --username=ente_auth; then
        break
    fi
    sleep 1
done
"${compose[@]}" exec -T postgres \
    pg_isready --quiet --dbname=ente_auth_test --username=ente_auth

"${compose[@]}" exec -T postgres \
    pg_restore --exit-on-error --no-owner --no-privileges \
    --username=ente_auth --dbname=ente_auth_test < "$dump"

account_state=$(
    "${compose[@]}" exec -T postgres \
        psql --tuples-only --no-align --field-separator='|' \
        --username=ente_auth --dbname=ente_auth_test \
        --command="SELECT (SELECT COUNT(*) FROM users), (SELECT COUNT(*) FROM users WHERE source = 'authMaestroFixture'), (SELECT COUNT(*) FROM users WHERE is_two_factor_enabled), (SELECT COUNT(*) FROM authenticator_key), (SELECT COUNT(*) FROM authenticator_entity), (SELECT COUNT(*) FROM authenticator_entity WHERE is_deleted);"
)
if [[ "$account_state" != "3|3|1|3|5|0" ]]; then
    echo "Restored database does not contain the exact fixture-v2 account, key, and entity state" >&2
    exit 1
fi

"${compose[@]}" up --detach museum
for _ in {1..60}; do
    if curl --fail --silent http://127.0.0.1:8080/ping >/dev/null; then
        echo "Restored Auth fixture v2 and started local Museum"
        trap - EXIT
        exit 0
    fi
    sleep 1
done

"${compose[@]}" ps
exit 1
