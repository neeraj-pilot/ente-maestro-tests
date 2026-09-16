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
assert_suites "basics" --changed-file maestro/auth/offline/manual-validation.yaml
assert_suites "basics" --changed-file maestro/auth/smoke/onboarding.yaml
assert_suites "organization" --changed-file maestro/auth/offline/bulk-pin-edit.yaml
assert_suites "basics" --changed-file maestro/auth/offline/duplicate-codes.yaml
assert_suites "basics" --changed-file maestro/auth/offline/manual-setup.yaml --changed-file maestro/auth/offline/settings.yaml
assert_suites "trash" --changed-file maestro/auth/offline/bulk-trash-restore.yaml
assert_suites "trash" --changed-file maestro/auth/offline/bulk-permanent-delete.yaml
assert_suites "tags,trash" --changed-file maestro/auth/offline/tags.yaml --changed-file maestro/auth/offline/trash-restore.yaml
assert_suites "basics,organization,tags,trash" --changed-file maestro/auth/subflows/add-offline-account.yaml
assert_suites "basics,organization,tags,trash" --changed-file maestro/auth/subflows/new-shared-helper.yaml
assert_suites "basics,organization,tags,trash" --changed-file maestro/auth/offline/new-hosted-flow.yaml
assert_suites "basics,organization,tags,trash" --changed-file scripts/resolve-nightly-apk.sh
assert_suites "basics,organization,tags,trash" --changed-file scripts/test-hosted-flow-registration.sh
assert_suites "basics,organization,tags,trash" --changed-file scripts/test-resolve-nightly-apk.sh
assert_suites "basics,organization,tags,trash" --all
assert_suites "basics" --suite basics
assert_suites "organization" --suite organization
assert_suites "" --changed-file README.md
assert_suites "" --changed-file maestro/auth/online/prepared-totp-login-complete.yaml
assert_suites "" --changed-file maestro/auth/online/subflows/add-online-code.yaml
assert_suites "" --changed-file maestro/auth/online/subflows/assert-synced-code.yaml
assert_suites "" --changed-file maestro/auth/online/subflows/dismiss-code-guidance.yaml
assert_suites "" --changed-file maestro/auth/online/subflows/login-online-account.yaml
assert_suites "" --changed-file maestro/auth/offline/local-backup.yaml
assert_suites "" --changed-file maestro/fixtures/plain_text_import.txt
assert_suites "basics,organization,tags,trash" --changed-file maestro/fixtures/new-fixture.json
assert_flows basics "maestro/auth/smoke/onboarding.yaml maestro/auth/smoke/offline-mode.yaml maestro/auth/offline/manual-setup.yaml maestro/auth/offline/manual-validation.yaml maestro/auth/offline/settings.yaml maestro/auth/offline/duplicate-codes.yaml" --all
assert_flows tags "maestro/auth/offline/tags.yaml maestro/auth/offline/bulk-tag-edit.yaml maestro/auth/offline/bulk-tag-remove.yaml" --changed-file maestro/auth/offline/tags.yaml
assert_flows organization "maestro/auth/offline/code-lifecycle.yaml maestro/auth/offline/home-organization.yaml maestro/auth/offline/bulk-pin-edit.yaml" --changed-file maestro/auth/offline/code-lifecycle.yaml
assert_flows trash "maestro/auth/offline/trash-restore.yaml maestro/auth/offline/bulk-trash-restore.yaml maestro/auth/offline/bulk-permanent-delete.yaml" --changed-file maestro/auth/offline/bulk-trash-restore.yaml

for path in .github/workflows/auth-android.yml .github/scripts/select-auth-tests.sh scripts/test-select-auth-tests.sh scripts/run-maestro.sh scripts/run-auth-android-local.sh scripts/download-auth-apk.sh scripts/install-maestro.sh scripts/test-ci-helpers.sh; do
    assert_suites "basics,organization,tags,trash" --changed-file "$path"
done

echo "Auth CI suite selection tests passed"
