#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
compose_file="$repo_root/museum/compose.yaml"
fixtures_dir="$repo_root/museum/fixtures"
credentials="$fixtures_dir/public-test-credentials.json"
dump="$fixtures_dir/auth-fixture-v1.dump"
manifest="$fixtures_dir/manifest.json"
project="ente-auth-fixture-generator"
verification_project="ente-auth-fixture-generation-verify"
ente_revision="fd4988b6cea005576ea293dd32add131b89dd66c"
museum_image="ghcr.io/ente/server@sha256:e9e06eb01834c38f41a3a09f9a64885b631346ce0005ccff2153faea403bd6e2"
postgres_image="postgres:15-alpine@sha256:3d0f7584ed7d04e27fa050d6683a74746608faf21f202be78460d679cc56461f"

compose=(docker compose --project-name "$project" --file "$compose_file")
verification_compose=(docker compose --project-name "$verification_project" --file "$compose_file")

cleanup() {
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
    "${verification_compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
mkdir -p "$fixtures_dir"
"${compose[@]}" up --detach

for _ in {1..60}; do
    if curl --fail --silent http://127.0.0.1:8080/ping >/dev/null; then
        break
    fi
    sleep 1
done
curl --fail --silent http://127.0.0.1:8080/ping >/dev/null

(
    cd "$repo_root/tools/auth-fixture-generator"
    AUTH_FIXTURE_ENDPOINT=http://127.0.0.1:8080 \
        cargo run --locked --release -- generate "$credentials"
)

"${compose[@]}" stop museum
temporary_dump="$dump.tmp"
"${compose[@]}" exec -T postgres \
    pg_dump --format=custom --no-owner --no-privileges \
    --username=ente_auth --dbname=ente_auth_test > "$temporary_dump"
mv "$temporary_dump" "$dump"

if command -v sha256sum >/dev/null; then
    dump_sha256=$(sha256sum "$dump" | awk '{print $1}')
else
    dump_sha256=$(shasum -a 256 "$dump" | awk '{print $1}')
fi
printf '%s  %s\n' "$dump_sha256" "$(basename "$dump")" > "$fixtures_dir/auth-fixture-v1.sha256"

jq --null-input \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg dumpSha256 "$dump_sha256" \
    --arg museumImage "$museum_image" \
    --arg postgresImage "$postgres_image" \
    --arg enteRevision "$ente_revision" \
    --slurpfile credentials "$credentials" \
    '{
        classification: "PUBLIC_LOCAL_TEST_FIXTURE",
        fixtureVersion: 1,
        generatedAt: $generatedAt,
        databaseDump: "auth-fixture-v1.dump",
        dumpSha256: $dumpSha256,
        museumImage: $museumImage,
        postgresImage: $postgresImage,
        enteSourceRevision: $enteRevision,
        generator: "tools/auth-fixture-generator",
        accountEmails: ($credentials[0].accounts | to_entries | map(.value.email) | sort)
    }' > "$manifest.tmp"
mv "$manifest.tmp" "$manifest"

"$repo_root/scripts/fixtures/verify-auth-fixture.sh"
cleanup
ALLOW_AUTH_FIXTURE_RESTORE=1 AUTH_FIXTURE_COMPOSE_PROJECT="$verification_project" \
    "$repo_root/scripts/fixtures/restore-auth-fixture.sh"
(
    cd "$repo_root/tools/auth-fixture-generator"
    AUTH_FIXTURE_ENDPOINT=http://127.0.0.1:8080 \
        cargo run --locked --release -- verify "$credentials"
)
echo "Generated Auth fixture v1 in $fixtures_dir"
