#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
fixtures_dir="$repo_root/museum/fixtures"
credentials="$fixtures_dir/public-test-credentials.json"
dump="$fixtures_dir/auth-fixture-v2.dump"
manifest="$fixtures_dir/manifest.json"

for path in "$credentials" "$dump" "$manifest" "$fixtures_dir/auth-fixture-v2.sha256"; do
    if [[ ! -f "$path" ]]; then
        echo "Missing Auth fixture file: $path" >&2
        exit 1
    fi
done

if command -v sha256sum >/dev/null; then
    actual_sha256=$(sha256sum "$dump" | awk '{print $1}')
else
    actual_sha256=$(shasum -a 256 "$dump" | awk '{print $1}')
fi
expected_sha256=$(jq --raw-output '.dumpSha256' "$manifest")
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Auth fixture dump checksum does not match manifest" >&2
    exit 1
fi

if [[ $(jq --raw-output '.classification' "$credentials") != "PUBLIC_LOCAL_TEST_FIXTURE" ]]; then
    echo "Auth fixture credentials are not classified as public local fixtures" >&2
    exit 1
fi
if [[ $(jq --raw-output '.allowedEndpoint' "$credentials") != "http://127.0.0.1:8080" ]]; then
    echo "Auth fixture endpoint is not restricted to loopback" >&2
    exit 1
fi
if [[ $(jq --raw-output '.fixtureVersion' "$credentials") != "2" ]]; then
    echo "Auth fixture credentials are not version 2" >&2
    exit 1
fi

email_count=$(jq '.accounts | length' "$credentials")
if [[ "$email_count" -ne 3 ]]; then
    echo "Expected exactly three Auth fixture accounts" >&2
    exit 1
fi
emails=$(jq --raw-output '.accounts[].email' "$credentials" | sort)
while IFS= read -r email; do
    if [[ ! "$email" =~ ^auth-maestro-fixture-.+-v2@example\.org$ ]]; then
        echo "Auth fixture identity is not unmistakably test-only: $email" >&2
        exit 1
    fi
done <<< "$emails"

user_ids=$(jq --raw-output '.accounts[].userId' "$credentials" | sort --numeric-sort --unique)
if [[ $(wc -l <<< "$user_ids" | tr -d ' ') -ne 3 ]] || grep --invert-match --extended-regexp --quiet '^[1-9][0-9]*$' <<< "$user_ids"; then
    echo "Auth fixture must contain three distinct positive user IDs" >&2
    exit 1
fi

manifest_emails=$(jq --compact-output '.accountEmails' "$manifest")
credential_emails=$(printf '%s\n' "$emails" | jq --compact-output --raw-input --slurp 'split("\n") | map(select(length > 0))')
if [[ "$manifest_emails" != "$credential_emails" ]]; then
    echo "Auth fixture manifest account list does not match credentials" >&2
    exit 1
fi

credential_code_count=$(jq '[.accounts[].codes[]] | length' "$credentials")
manifest_code_count=$(jq '.codeCount' "$manifest")
if [[ "$credential_code_count" -ne 7 || "$manifest_code_count" -ne "$credential_code_count" ]]; then
    echo "Auth fixture must describe exactly seven encrypted code entities" >&2
    exit 1
fi
credential_code_counts=$(jq --compact-output '.accounts | with_entries(.value = (.value.codes | length))' "$credentials")
manifest_code_counts=$(jq --compact-output '.accountCodeCounts' "$manifest")
if [[ "$manifest_code_counts" != "$credential_code_counts" ]]; then
    echo "Auth fixture manifest code counts do not match credentials" >&2
    exit 1
fi

museum_image=$(jq --raw-output '.museumImage' "$manifest")
postgres_image=$(jq --raw-output '.postgresImage' "$manifest")
if ! grep --fixed-strings --quiet "image: $museum_image" "$repo_root/museum/compose.yaml"; then
    echo "Museum image differs from the fixture manifest" >&2
    exit 1
fi
if ! grep --fixed-strings --quiet "image: $postgres_image" "$repo_root/museum/compose.yaml"; then
    echo "PostgreSQL image differs from the fixture manifest" >&2
    exit 1
fi

echo "Auth fixture files and public identities are internally consistent"
