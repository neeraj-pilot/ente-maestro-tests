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
assert_suites "setup" --changed-file maestro/auth/offline/manual-validation.yaml
assert_suites "tags,trash" --changed-file maestro/auth/offline/tags.yaml --changed-file maestro/auth/offline/trash-restore.yaml
assert_suites "setup,organization,settings,tags,trash" --changed-file maestro/auth/subflows/add-offline-account.yaml
assert_suites "setup,organization,settings,tags,trash" --changed-file maestro/auth/offline/new-hosted-flow.yaml
assert_suites "setup,organization,settings,tags,trash" --all
assert_suites "" --changed-file README.md
assert_suites "" --changed-file maestro/auth/offline/local-backup.yaml
assert_suites "" --changed-file maestro/auth/fixtures/plain_text_import.txt
assert_suites "setup,organization,settings,tags,trash" --changed-file maestro/auth/fixtures/new-fixture.json
assert_flows tags "maestro/auth/offline/tags.yaml" --changed-file maestro/auth/offline/tags.yaml

echo "Auth CI suite selection tests passed"
