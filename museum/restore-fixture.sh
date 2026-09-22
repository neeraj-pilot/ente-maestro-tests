#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$repo_root/museum/compose.yaml"
fixtures_dir=${AUTH_FIXTURE_DIR:-$repo_root/museum/fixtures}
dump="$fixtures_dir/auth-fixture-v2.dump"
credentials="$fixtures_dir/public-test-credentials.json"
test -f "$dump"

jq --exit-status '
    .classification == "PUBLIC_LOCAL_TEST_FIXTURE" and
    .allowedEndpoint == "http://127.0.0.1:8080" and
    .fixtureVersion == 2 and
    (.accounts | length == 3) and
    all(.accounts[];
        (.email | test("^auth-maestro-fixture-.+-v2@example[.]org$")) and
        (.userId | tostring | test("^[1-9][0-9]*$"))) and
    ([.accounts[].userId | tostring] | unique | length == 3) and
    ([.accounts[].codes[]] | length == 5)
' "$credentials" > /dev/null || {
    echo "Invalid public Auth fixture credentials" >&2
    exit 1
}

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

"${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
"${compose[@]}" up --wait --wait-timeout 60 postgres

"${compose[@]}" exec -T postgres \
    pg_restore --exit-on-error --no-owner --no-privileges \
    --username=ente_auth --dbname=ente_auth_test < "$dump"

"${compose[@]}" up --wait --wait-timeout 60 museum
echo "Restored Auth fixture v2 and started local Museum"
trap - EXIT
