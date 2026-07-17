#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-auth-ci-suites.sh"

assert_suites() {
    local expected="$1"
    shift
    local actual
    actual="$("$selector" "$@" | jq -r '.include | map(.suite) | join(",")')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected suites '$expected', got '$actual' for: $*" >&2
        exit 1
    fi
}

assert_flows() {
    local suite="$1"
    local expected="$2"
    shift 2
    local actual
    actual="$("$selector" "$@" | jq -r --arg suite "$suite" '.include[] | select(.suite == $suite) | .flows')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected flows '$expected', got '$actual' for suite '$suite'" >&2
        exit 1
    fi
}

assert_suites "tags" --changed-file maestro/auth/offline/tags.yaml
assert_suites "tags" --changed-file maestro/auth/offline/bulk-tag-edit.yaml
assert_suites "tags" --changed-file maestro/auth/offline/bulk-tag-remove.yaml
assert_suites "setup" --changed-file maestro/auth/offline/manual-validation.yaml
assert_suites "organization" --changed-file maestro/auth/offline/bulk-pin-edit.yaml
assert_suites "settings" --changed-file maestro/auth/offline/duplicate-codes.yaml
assert_suites "trash" --changed-file maestro/auth/offline/bulk-trash-restore.yaml
assert_suites "tags,trash" --changed-file maestro/auth/offline/tags.yaml --changed-file maestro/auth/offline/trash-restore.yaml
assert_suites "setup,organization,settings,tags,trash" --changed-file maestro/auth/subflows/add-offline-account.yaml
assert_suites "setup,organization,settings,tags,trash" --changed-file maestro/auth/offline/new-hosted-flow.yaml
assert_suites "setup,organization,settings,tags,trash" --all
assert_suites "" --changed-file README.md
assert_suites "" --changed-file maestro/auth/offline/local-backup.yaml
assert_suites "" --changed-file maestro/auth/fixtures/plain_text_import.txt
assert_suites "setup,organization,settings,tags,trash" --changed-file maestro/auth/fixtures/new-fixture.json
assert_flows tags "maestro/auth/offline/tags.yaml maestro/auth/offline/bulk-tag-edit.yaml maestro/auth/offline/bulk-tag-remove.yaml" --changed-file maestro/auth/offline/tags.yaml
assert_flows organization "maestro/auth/offline/code-lifecycle.yaml maestro/auth/offline/home-organization.yaml maestro/auth/offline/bulk-pin-edit.yaml" --changed-file maestro/auth/offline/code-lifecycle.yaml
assert_flows settings "maestro/auth/offline/settings.yaml maestro/auth/offline/duplicate-codes.yaml" --changed-file maestro/auth/offline/duplicate-codes.yaml
assert_flows trash "maestro/auth/offline/trash-restore.yaml maestro/auth/offline/bulk-trash-restore.yaml" --changed-file maestro/auth/offline/bulk-trash-restore.yaml

echo "Auth CI suite selection tests passed"
