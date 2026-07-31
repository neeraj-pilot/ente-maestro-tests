#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly offline_selector="$workspace_root/scripts/select-auth-ci-suites.sh"
readonly online_selector="$workspace_root/scripts/select-auth-online-lanes.sh"

reachable=""
queue=()

contains_line() {
    local lines=$1
    local candidate=$2
    [[ $'\n'"$lines"$'\n' == *$'\n'"$candidate"$'\n'* ]]
}

enqueue() {
    local flow=$1
    if ! contains_line "$reachable" "$flow"; then
        reachable+="${reachable:+$'\n'}$flow"
        queue+=("$flow")
    fi
}

collect_reachable() {
    local allowed_scope=$1
    local dependency dependency_absolute dependency_path flow

    while [[ ${#queue[@]} -gt 0 ]]; do
        flow=${queue[0]}
        queue=("${queue[@]:1}")
        if [[ ! -f "$workspace_root/$flow" ]]; then
            echo "Registered Maestro flow does not exist: $flow" >&2
            exit 1
        fi

        while IFS= read -r dependency; do
            dependency_absolute=$(realpath "$(dirname "$workspace_root/$flow")/$dependency")
            dependency_path=${dependency_absolute#"$workspace_root/"}
            case "$allowed_scope:$dependency_path" in
                offline:maestro/auth/offline/*|offline:maestro/auth/smoke/*|offline:maestro/auth/subflows/*|online:maestro/auth/online/*)
                    enqueue "$dependency_path"
                    ;;
                *)
                    echo "Maestro flow escapes its hosted scope: $flow -> $dependency_path" >&2
                    exit 1
                    ;;
            esac
        done < <(sed -En "s/^[[:space:]]*file:[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\1/p" "$workspace_root/$flow")
    done
}

offline_matrix=$($offline_selector --all)
while IFS= read -r flow; do
    [[ -n "$flow" ]] && enqueue "$flow"
done < <(jq -r '.include[].flows' <<< "$offline_matrix" | tr ' ' '\n')
collect_reachable offline

while IFS= read -r flow; do
    case "$flow" in
        maestro/auth/offline/imports.yaml|maestro/auth/offline/local-backup.yaml) continue ;;
    esac
    if ! contains_line "$reachable" "$flow"; then
        echo "Offline Maestro flow is not registered in a hosted suite: $flow" >&2
        exit 1
    fi
done < <(find "$workspace_root/maestro/auth/offline" "$workspace_root/maestro/auth/smoke" "$workspace_root/maestro/auth/subflows" -name '*.yaml' -type f | sed "s|^$workspace_root/||" | sort)

reachable=""
queue=()
while IFS= read -r flow; do
    [[ -n "$flow" ]] && enqueue "$flow"
done < <(grep -Eo 'maestro/auth/online/[[:alnum:]_./-]+\.yaml' "$workspace_root/.github/scripts/run-auth-online-tests.sh" | sort -u)

if [[ ${#queue[@]} -eq 0 ]]; then
    echo "The hosted online runner does not invoke any Maestro flows" >&2
    exit 1
fi
collect_reachable online

while IFS= read -r flow; do
    if ! contains_line "$reachable" "$flow"; then
        echo "Online Maestro flow is unreachable from the hosted runner: $flow" >&2
        exit 1
    fi
    if ! $online_selector --changed-file "$flow" | jq -e 'length > 0' > /dev/null; then
        echo "Online Maestro flow does not select a hosted lane: $flow" >&2
        exit 1
    fi
done < <(find "$workspace_root/maestro/auth/online" -name '*.yaml' -type f | sed "s|^$workspace_root/||" | sort)

echo "Hosted Maestro flow registration tests passed"
