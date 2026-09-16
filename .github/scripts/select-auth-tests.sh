#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
offline='{"include":[]}'
online='[]'

case "$EVENT_NAME" in
    workflow_dispatch)
        case "${REQUESTED_SUITE:-all}" in
            all|offline) offline=$("$root/scripts/select-auth-ci-suites.sh" --all) ;;
            basics|organization|tags|trash) offline=$("$root/scripts/select-auth-ci-suites.sh" --suite "$REQUESTED_SUITE") ;;
            online|account-auth|recovery-password|data-sync|entity-lifecycle|startup) ;;
            *) echo "Unknown Auth suite: $REQUESTED_SUITE" >&2; exit 2 ;;
        esac
        case "${REQUESTED_SUITE:-all}" in
            all|online) online=$("$root/scripts/select-auth-online-lanes.sh" --all) ;;
            account-auth|recovery-password|data-sync|entity-lifecycle|startup)
                online=$(jq -cn --arg suite "$REQUESTED_SUITE" '[$suite]')
                ;;
        esac
        ;;
    schedule)
        offline=$("$root/scripts/select-auth-ci-suites.sh" --all)
        online=$("$root/scripts/select-auth-online-lanes.sh" --all)
        ;;
    push|pull_request)
        if [[ "$BASE_SHA" =~ ^0+$ ]]; then
            offline=$("$root/scripts/select-auth-ci-suites.sh" --all)
            online=$("$root/scripts/select-auth-online-lanes.sh" --all)
        else
            # Check revisions here: a failed diff in a selector's process substitution
            # must not be mistaken for an empty selection.
            git diff --name-only "$BASE_SHA" "$HEAD_SHA" > /dev/null
            offline=$("$root/scripts/select-auth-ci-suites.sh" "$BASE_SHA" "$HEAD_SHA")
            online=$("$root/scripts/select-auth-online-lanes.sh" "$BASE_SHA" "$HEAD_SHA")
            if [[ "$EVENT_NAME" == push ]]; then
                if [[ $(jq '.include | length' <<< "$offline") -gt 0 ]]; then
                    offline=$("$root/scripts/select-auth-ci-suites.sh" --all)
                fi
                if [[ $(jq length <<< "$online") -gt 0 ]]; then
                    online=$("$root/scripts/select-auth-online-lanes.sh" --all)
                fi
            fi
        fi
        ;;
    *) echo "Unsupported event: $EVENT_NAME" >&2; exit 2 ;;
esac

{
    echo "offline=$offline"
    echo "online=$online"
    echo "has_offline=$(jq '.include | length > 0' <<< "$offline")"
    echo "has_online=$(jq 'length > 0' <<< "$online")"
} >> "$GITHUB_OUTPUT"
