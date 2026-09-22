#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$repo_root/museum/compose.yaml"
fixtures_dir="$repo_root/museum/fixtures"
project="ente-auth-fixture-generator"

compose=(docker compose --project-name "$project" --file "$compose_file")
config=$("${compose[@]}" config --format json)
museum_image=$(jq -er '.services.museum.image' <<< "$config")
postgres_image=$(jq -er '.services.postgres.image' <<< "$config")
ente_revision=$(cargo metadata --locked --format-version 1 \
    --manifest-path "$repo_root/tools/auth-fixture-generator/Cargo.toml" | jq -er '
        [.packages[] | select(.name == "ente-accounts" or .name == "ente-core")
            | .source | split("#")[1]] | unique |
        if length == 1 and (.[0] | test("^[0-9a-f]{40}$"))
        then .[0] else error("Expected one pinned Ente revision") end
    ')
staging_dir=$(mktemp -d)
export AUTH_FIXTURE_DIR="$staging_dir"
credentials="$staging_dir/public-test-credentials.json"
dump="$staging_dir/auth-fixture-v2.dump"
manifest="$staging_dir/manifest.json"
cleanup() {
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
    rm -rf "$staging_dir"
}
trap cleanup EXIT

"${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
"${compose[@]}" up --wait --wait-timeout 60
museum_server_revision=$(curl --fail --silent http://127.0.0.1:8080/ping | jq -er '.id')

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

AUTH_FIXTURE_COMPOSE_PROJECT="$project" \
    "$repo_root/museum/restore-fixture.sh"
(
    cd "$repo_root/tools/auth-fixture-generator"
    AUTH_FIXTURE_ENDPOINT=http://127.0.0.1:8080 \
        cargo run --locked --release -- verify "$credentials"
)
mv "$credentials" "$dump" "$manifest" "$fixtures_dir/"
echo "Generated Auth fixture v2 in $fixtures_dir"
