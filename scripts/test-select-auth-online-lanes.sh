#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-auth-online-lanes.sh"

assert_lanes() {
    local expected="$1"
    shift
    local actual
    actual="$("$selector" "$@" | jq -r 'join(",")')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected lanes '$expected', got '$actual' for: $*" >&2
        exit 1
    fi
}

assert_lanes "account-auth,data-sync" --all
assert_lanes "account-auth" --changed-file maestro/auth/online/prepared-totp-login-start.yaml
assert_lanes "account-auth" --changed-file maestro/auth/online/prepared-recovery-password-reset.yaml
assert_lanes "account-auth" --changed-file maestro/auth/subflows/add-online-code.yaml
assert_lanes "account-auth" --changed-file scripts/current-totp.mjs
assert_lanes "data-sync" --changed-file maestro/auth/online/prepared-password-login.yaml
assert_lanes "data-sync" --changed-file maestro/auth/online/prepared-bulk-mutation-start.yaml
assert_lanes "account-auth,data-sync" --changed-file maestro/auth/online/unknown-login.yaml --changed-file maestro/auth/online/prepared-password-login.yaml
assert_lanes "account-auth,data-sync" --changed-file maestro/auth/subflows/login-online-account.yaml
assert_lanes "account-auth,data-sync" --changed-file museum/fixtures/manifest.json
assert_lanes "account-auth,data-sync" --changed-file maestro/auth/online/new-online-flow.yaml
assert_lanes "" --changed-file README.md

echo "Auth online lane selection tests passed"
