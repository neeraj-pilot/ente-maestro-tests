#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
expected=$(jq -r '
    (.accounts | length) as $users |
    [.accounts[].codes[]] as $codes |
    [.accounts[] | select(.totpSecret != null)] as $totp |
    [$users, $users, ($totp | length), $users, ($codes | length), 0] | join("|")
' "$repo_root/museum/fixtures/public-test-credentials.json")

actual=$("$@" --tuples-only --no-align --field-separator='|' \
    --username=ente_auth --dbname=ente_auth_test \
    --command="SELECT (SELECT COUNT(*) FROM users), (SELECT COUNT(*) FROM users WHERE source = 'authMaestroFixture'), (SELECT COUNT(*) FROM users WHERE is_two_factor_enabled), (SELECT COUNT(*) FROM authenticator_key), (SELECT COUNT(*) FROM authenticator_entity), (SELECT COUNT(*) FROM authenticator_entity WHERE is_deleted);")
if [[ "$actual" != "$expected" ]]; then
    echo "Restored Auth fixture state: expected $expected, got $actual" >&2
    exit 1
fi
