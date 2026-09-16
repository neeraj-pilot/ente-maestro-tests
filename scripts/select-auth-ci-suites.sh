#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/select-auth-ci-suites.sh --all
  scripts/select-auth-ci-suites.sh --suite <basics|organization|tags|trash>
  scripts/select-auth-ci-suites.sh --changed-file <path> [--changed-file <path> ...]
  scripts/select-auth-ci-suites.sh <base-revision> <head-revision>

Print the hosted Auth Android CI matrix for the supplied changes.
EOF
}

if ! command -v jq > /dev/null; then
    echo "Required command is not available: jq" >&2
    exit 2
fi

full_matrix=false
requested_suite=""
changed_files=()

case "${1:-}" in
    --all)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        full_matrix=true
        ;;
    --suite)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        requested_suite=$2
        ;;
    --changed-file)
        while [[ $# -gt 0 ]]; do
            [[ "$1" == "--changed-file" && $# -ge 2 ]] || {
                usage >&2
                exit 2
            }
            changed_files+=("$2")
            shift 2
        done
        ;;
    *)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        while IFS= read -r changed_file; do
            [[ -n "$changed_file" ]] && changed_files+=("$changed_file")
        done < <(git diff --name-only "$1" "$2")
        ;;
esac

readonly suite_order=(basics organization tags trash)
selected_suites=""

add_suite() {
    local suite="$1"
    if [[ ",$selected_suites," != *",$suite,"* ]]; then
        selected_suites+="${selected_suites:+,}$suite"
    fi
}

if [[ -n "$requested_suite" ]]; then
    case "$requested_suite" in
        basics|organization|tags|trash) add_suite "$requested_suite" ;;
        *) echo "Unknown hosted Auth suite: $requested_suite" >&2; exit 2 ;;
    esac
fi

if [[ ${#changed_files[@]} -gt 0 ]]; then
    for changed_file in "${changed_files[@]}"; do
        case "$changed_file" in
            .github/workflows/auth-android.yml|.github/scripts/select-auth-tests.sh|scripts/test-select-auth-tests.sh|scripts/run-maestro.sh|scripts/run-auth-android-local.sh|scripts/resolve-nightly-apk.sh|scripts/download-auth-apk.sh|scripts/install-maestro.sh|scripts/test-ci-helpers.sh|scripts/select-auth-ci-suites.sh|scripts/test-hosted-flow-registration.sh|scripts/test-resolve-nightly-apk.sh|scripts/test-select-auth-ci-suites.sh|maestro/auth/subflows/*)
                full_matrix=true
                ;;
            maestro/auth/online/*)
                ;;
            maestro/auth/smoke/*|maestro/auth/offline/manual-setup.yaml|maestro/auth/offline/manual-validation.yaml|maestro/auth/offline/settings.yaml|maestro/auth/offline/duplicate-codes.yaml)
                add_suite basics
                ;;
            maestro/auth/offline/code-lifecycle.yaml|maestro/auth/offline/home-organization.yaml|maestro/auth/offline/bulk-pin-edit.yaml)
                add_suite organization
                ;;
            maestro/auth/offline/tags.yaml|maestro/auth/offline/bulk-tag-edit.yaml|maestro/auth/offline/bulk-tag-remove.yaml)
                add_suite tags
                ;;
            maestro/auth/offline/trash-restore.yaml|maestro/auth/offline/bulk-trash-restore.yaml|maestro/auth/offline/bulk-permanent-delete.yaml)
                add_suite trash
                ;;
            # These flows need local Android picker validation before promotion
            # to the hosted x86_64 matrix.
            maestro/auth/offline/imports.yaml|maestro/auth/offline/local-backup.yaml|maestro/fixtures/plain_text_import.txt|maestro/fixtures/google_auth_migration.png)
                ;;
            # A new hosted flow must not silently receive no coverage.
            maestro/auth/offline/*.yaml|maestro/fixtures/*|maestro/auth/*.yaml)
                full_matrix=true
                ;;
        esac
    done
fi

if [[ "$full_matrix" == true ]]; then
    selected_suites="$(IFS=,; echo "${suite_order[*]}")"
fi

matrix='{"include":[]}'
for suite in "${suite_order[@]}"; do
    [[ ",$selected_suites," == *",$suite,"* ]] || continue
    case "$suite" in
        basics)
            name="Offline basics"
            flows="maestro/auth/smoke/onboarding.yaml maestro/auth/smoke/offline-mode.yaml maestro/auth/offline/manual-setup.yaml maestro/auth/offline/manual-validation.yaml maestro/auth/offline/settings.yaml maestro/auth/offline/duplicate-codes.yaml"
            coverage="onboarding, offline entry, manual setup, field validation, settings, themes, and duplicate groups"
            ;;
        organization)
            name="Offline lifecycle and organization"
            flows="maestro/auth/offline/code-lifecycle.yaml maestro/auth/offline/home-organization.yaml maestro/auth/offline/bulk-pin-edit.yaml"
            coverage="offline code edit and cold-relaunch persistence, bulk pinning, issuer/account search, empty results, and sorting"
            ;;
        tags)
            name="Offline tags"
            flows="maestro/auth/offline/tags.yaml maestro/auth/offline/bulk-tag-edit.yaml maestro/auth/offline/bulk-tag-remove.yaml"
            coverage="create, filter, bulk-apply, and bulk-remove tags from offline codes"
            ;;
        trash)
            name="Offline trash"
            flows="maestro/auth/offline/trash-restore.yaml maestro/auth/offline/bulk-trash-restore.yaml maestro/auth/offline/bulk-permanent-delete.yaml"
            coverage="trash, restore, and permanently delete one or multiple offline codes"
            ;;
    esac
    matrix="$(jq -c \
        --arg name "$name" \
        --arg suite "$suite" \
        --arg flows "$flows" \
        --arg coverage "$coverage" \
        '.include += [{name: $name, suite: $suite, flows: $flows, coverage: $coverage}]' \
        <<< "$matrix")"
done

printf '%s\n' "$matrix"
