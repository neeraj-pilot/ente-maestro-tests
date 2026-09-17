#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
fixtures_dir=${AUTH_FIXTURE_DIR:-$repo_root/museum/fixtures}
credentials="$fixtures_dir/public-test-credentials.json"
dump="$fixtures_dir/auth-fixture-v2.dump"
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

echo "Auth fixture files and public identities are internally consistent"
