#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/select-auth-online-lanes.sh --all
  scripts/select-auth-online-lanes.sh --changed-file <path> [--changed-file <path> ...]
  scripts/select-auth-online-lanes.sh <base-revision> <head-revision>

Print the hosted Auth Android online lanes for the supplied changes.
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

selected_lanes=""

add_lane() {
    local lane="$1"
    if [[ ",$selected_lanes," != *",$lane,"* ]]; then
        selected_lanes+="${selected_lanes:+,}$lane"
    fi
}

if [[ ${#changed_files[@]} -gt 0 ]]; then
    for changed_file in "${changed_files[@]}"; do
        case "$changed_file" in
            maestro/auth/online/password-login.yaml|maestro/auth/online/prepared-totp-login-complete.yaml|maestro/auth/online/prepared-totp-login-start.yaml|maestro/auth/online/signup-recovery-login.yaml|maestro/auth/online/unknown-login.yaml|maestro/auth/online/subflows/add-online-code.yaml|scripts/current-totp.mjs)
                add_lane account-auth
                ;;
            maestro/auth/online/prepared-recovery-password-reset.yaml)
                add_lane recovery-password
                ;;
            maestro/auth/online/prepared-basic-login.yaml|maestro/auth/online/prepared-bulk-mutation-complete.yaml|maestro/auth/online/prepared-bulk-mutation-start.yaml|maestro/auth/online/prepared-password-login.yaml)
                add_lane data-sync
                ;;
            .github/scripts/run-auth-online-tests.sh|.github/workflows/auth-android-online.yml|maestro/auth/online/subflows/assert-synced-code.yaml|maestro/auth/online/subflows/configure-online-test-endpoint.yaml|maestro/auth/online/subflows/dismiss-code-guidance.yaml|maestro/auth/online/subflows/login-online-account.yaml|museum/*|scripts/fixtures/*|scripts/resolve-auth-nightly.sh|scripts/select-auth-online-lanes.sh|scripts/test-select-auth-online-lanes.sh)
                full_matrix=true
                ;;
            # A new online flow must not silently receive partial coverage.
            maestro/auth/online/*.yaml|maestro/auth/online/subflows/*.yaml)
                full_matrix=true
                ;;
        esac
    done
fi

if [[ "$full_matrix" == true ]]; then
    selected_lanes="account-auth,recovery-password,data-sync"
fi

lanes='[]'
for lane in account-auth recovery-password data-sync; do
    [[ ",$selected_lanes," == *",$lane,"* ]] || continue
    lanes="$(jq -c --arg lane "$lane" '. + [$lane]' <<< "$lanes")"
done

printf '%s\n' "$lanes"
