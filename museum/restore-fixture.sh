#!/usr/bin/env bash

set -euo pipefail

if [[ ${ALLOW_AUTH_FIXTURE_RESTORE:-} != "1" ]]; then
    echo "Set ALLOW_AUTH_FIXTURE_RESTORE=1 to restore the public local Auth fixture" >&2
    exit 1
fi

repo_root=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$repo_root/museum/compose.yaml"
fixtures_dir=${AUTH_FIXTURE_DIR:-$repo_root/museum/fixtures}
dump="$fixtures_dir/auth-fixture-v2.dump"
credentials="$fixtures_dir/public-test-credentials.json"
manifest="$fixtures_dir/manifest.json"

for path in "$credentials" "$dump" "$manifest"; do
    if [[ ! -f "$path" ]]; then
        echo "Missing Auth fixture file: $path" >&2
        exit 1
    fi
done

actual_sha256=$(shasum -a 256 "$dump" | awk '{print $1}')
expected_sha256=$(jq --raw-output '.dumpSha256' "$manifest")
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Auth fixture dump checksum does not match manifest" >&2
    exit 1
fi

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

museum_image=$(jq --raw-output '.museumImage' "$manifest")
museum_server_revision=$(jq --raw-output '.museumServerRevision' "$manifest")
postgres_image=$(jq --raw-output '.postgresImage' "$manifest")
if [[ ! "$museum_server_revision" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Museum source revision is not a full Git commit" >&2
    exit 1
fi
if ! grep -Fq "image: $museum_image" "$repo_root/museum/compose.yaml"; then
    echo "Museum image differs from the fixture manifest" >&2
    exit 1
fi
if ! grep -Fq "image: $postgres_image" "$repo_root/museum/compose.yaml"; then
    echo "PostgreSQL image differs from the fixture manifest" >&2
    exit 1
fi

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

expected=$(jq -r '
    (.accounts | length) as $users |
    [.accounts[].codes[]] as $codes |
    [.accounts[] | select(.totpSecret != null)] as $totp |
    [$users, $users, ($totp | length), $users, ($codes | length), 0] | join("|")
' "$credentials")

actual=$("${compose[@]}" exec -T postgres psql --tuples-only --no-align --field-separator='|' \
    --username=ente_auth --dbname=ente_auth_test \
    --command="SELECT (SELECT COUNT(*) FROM users), (SELECT COUNT(*) FROM users WHERE source = 'authMaestroFixture'), (SELECT COUNT(*) FROM users WHERE is_two_factor_enabled), (SELECT COUNT(*) FROM authenticator_key), (SELECT COUNT(*) FROM authenticator_entity), (SELECT COUNT(*) FROM authenticator_entity WHERE is_deleted);")
if [[ "$actual" != "$expected" ]]; then
    echo "Restored Auth fixture state: expected $expected, got $actual" >&2
    exit 1
fi

"${compose[@]}" up --wait --wait-timeout 60 museum
echo "Restored Auth fixture v2 and started local Museum"
trap - EXIT
