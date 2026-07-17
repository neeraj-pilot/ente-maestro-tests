#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/select-auth-ci-suites.sh --all
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
changed_files=()

case "${1:-}" in
    --all)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        full_matrix=true
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

readonly suite_order=(setup organization settings tags trash)
selected_suites=""

add_suite() {
    local suite="$1"
    if [[ ",$selected_suites," != *",$suite,"* ]]; then
        selected_suites+="${selected_suites:+,}$suite"
    fi
}

if [[ ${#changed_files[@]} -gt 0 ]]; then
    for changed_file in "${changed_files[@]}"; do
        case "$changed_file" in
            .github/workflows/auth-android-smoke.yml|scripts/select-auth-ci-suites.sh|scripts/test-select-auth-ci-suites.sh|maestro/auth/smoke/*|maestro/auth/subflows/*)
                full_matrix=true
                ;;
            maestro/auth/offline/manual-setup.yaml|maestro/auth/offline/manual-validation.yaml)
                add_suite setup
                ;;
            maestro/auth/offline/code-lifecycle.yaml|maestro/auth/offline/home-organization.yaml)
                add_suite organization
                ;;
            maestro/auth/offline/settings.yaml|maestro/auth/offline/duplicate-codes.yaml)
                add_suite settings
                ;;
            maestro/auth/offline/tags.yaml)
                add_suite tags
                ;;
            maestro/auth/offline/trash-restore.yaml)
                add_suite trash
                ;;
            # These flows need an Android platform validation, not the hosted
            # x86_64 matrix. A merge still runs the full hosted baseline on main.
            maestro/auth/offline/imports.yaml|maestro/auth/offline/local-backup.yaml|maestro/auth/fixtures/plain_text_import.txt|maestro/auth/fixtures/google_auth_migration.png)
                ;;
            # A new hosted flow must not silently receive no coverage.
            maestro/auth/offline/*.yaml|maestro/auth/fixtures/*|maestro/auth/*.yaml)
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
        setup)
            name="Offline setup and validation"
            flows="maestro/auth/smoke/onboarding.yaml maestro/auth/smoke/offline-mode.yaml maestro/auth/offline/manual-setup.yaml maestro/auth/offline/manual-validation.yaml"
            coverage="onboarding, offline entry, manual setup, and field validation"
            ;;
        organization)
            name="Offline lifecycle and organization"
            flows="maestro/auth/offline/code-lifecycle.yaml maestro/auth/offline/home-organization.yaml"
            coverage="code details and edits, issuer/account search, empty results, and sorting"
            ;;
        settings)
            name="Offline settings"
            flows="maestro/auth/offline/settings.yaml maestro/auth/offline/duplicate-codes.yaml"
            coverage="settings structure, General, About, Theme, version label, and duplicate groups"
            ;;
        tags)
            name="Offline tags"
            flows="maestro/auth/offline/tags.yaml"
            coverage="create a tag and filter the offline code list"
            ;;
        trash)
            name="Offline trash"
            flows="maestro/auth/offline/trash-restore.yaml"
            coverage="trash and restore an offline code without permanent deletion"
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
