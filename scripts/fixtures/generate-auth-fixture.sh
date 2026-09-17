#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
compose_file="$repo_root/museum/compose.yaml"
fixtures_dir="$repo_root/museum/fixtures"
manifest="$fixtures_dir/manifest.json"
project="ente-auth-fixture-generator"
verification_project="ente-auth-fixture-generation-verify"
ente_revision=$(jq -r '.enteSourceRevision' "$manifest")
museum_image=$(jq -r '.museumImage' "$manifest")
museum_server_revision=$(jq -r '.museumServerRevision' "$manifest")
postgres_image=$(jq -r '.postgresImage' "$manifest")

compose=(docker compose --project-name "$project" --file "$compose_file")
verification_compose=(docker compose --project-name "$verification_project" --file "$compose_file")

stop_backends() {
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
    "${verification_compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
staging_dir=$(mktemp -d)
export AUTH_FIXTURE_DIR="$staging_dir"
credentials="$staging_dir/public-test-credentials.json"
dump="$staging_dir/auth-fixture-v2.dump"
manifest="$staging_dir/manifest.json"
cleanup() {
    stop_backends
    rm -rf "$staging_dir"
}
trap cleanup EXIT

stop_backends
"${compose[@]}" up --detach

for _ in {1..60}; do
    if curl --fail --silent http://127.0.0.1:8080/ping >/dev/null; then
        break
    fi
    sleep 1
done
observed_museum_revision=$(curl --fail --silent http://127.0.0.1:8080/ping | jq --raw-output '.id')
if [[ "$observed_museum_revision" != "$museum_server_revision" ]]; then
    echo "Museum image does not match the pinned server revision" >&2
    exit 1
fi

(
    cd "$repo_root/tools/auth-fixture-generator"
    AUTH_FIXTURE_ENDPOINT=http://127.0.0.1:8080 \
        cargo run --locked --release -- generate "$credentials"
)

"${compose[@]}" stop museum
"${compose[@]}" exec -T postgres \
    pg_dump --format=custom --no-owner --no-privileges \
    --username=ente_auth --dbname=ente_auth_test > "$dump"

dump_sha256=$(shasum -a 256 "$dump" | awk '{print $1}')

jq --null-input \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg dumpSha256 "$dump_sha256" \
    --arg museumImage "$museum_image" \
    --arg museumServerRevision "$museum_server_revision" \
    --arg postgresImage "$postgres_image" \
    --arg enteRevision "$ente_revision" \
    '{
        classification: "PUBLIC_LOCAL_TEST_FIXTURE",
        fixtureVersion: 2,
        generatedAt: $generatedAt,
        databaseDump: "auth-fixture-v2.dump",
        dumpSha256: $dumpSha256,
        museumImage: $museumImage,
        museumServerRevision: $museumServerRevision,
        postgresImage: $postgresImage,
        enteSourceRevision: $enteRevision,
        generator: "tools/auth-fixture-generator"
    }' > "$manifest"

"$repo_root/scripts/fixtures/verify-auth-fixture.sh"
stop_backends
ALLOW_AUTH_FIXTURE_RESTORE=1 AUTH_FIXTURE_COMPOSE_PROJECT="$verification_project" \
    "$repo_root/scripts/fixtures/restore-auth-fixture.sh"
(
    cd "$repo_root/tools/auth-fixture-generator"
    AUTH_FIXTURE_ENDPOINT=http://127.0.0.1:8080 \
        cargo run --locked --release -- verify "$credentials"
)
mv "$credentials" "$dump" "$manifest" "$fixtures_dir/"
echo "Generated Auth fixture v2 in $fixtures_dir"
