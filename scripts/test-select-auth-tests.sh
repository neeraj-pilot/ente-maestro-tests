#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
export GITHUB_OUTPUT="$temp_dir/output"
readonly all_offline=basics,organization,tags,trash
readonly all_online=account-auth,recovery-password,data-sync,entity-lifecycle

assert_selection() {
    local expected_offline=$1 expected_online=$2
    shift 2
    : > "$GITHUB_OUTPUT"
    env "$@" "$root/.github/scripts/select-auth-tests.sh"
    local offline online
    offline=$(sed -n 's/^offline=//p' "$GITHUB_OUTPUT")
    online=$(sed -n 's/^online=//p' "$GITHUB_OUTPUT")
    [[ $(jq -r '.include | map(.suite) | join(",")' <<< "$offline") == "$expected_offline" ]]
    [[ $(jq -r 'join(",")' <<< "$online") == "$expected_online" ]]
    grep -Fxq "has_offline=$(jq '.include | length > 0' <<< "$offline")" "$GITHUB_OUTPUT"
    grep -Fxq "has_online=$(jq 'length > 0' <<< "$online")" "$GITHUB_OUTPUT"
}

assert_selection "$all_offline" "$all_online" EVENT_NAME=schedule
assert_selection "$all_offline" "$all_online" EVENT_NAME=workflow_dispatch REQUESTED_SUITE=all
assert_selection "$all_offline" "" EVENT_NAME=workflow_dispatch REQUESTED_SUITE=offline
assert_selection "" "$all_online" EVENT_NAME=workflow_dispatch REQUESTED_SUITE=online
assert_selection basics "" EVENT_NAME=workflow_dispatch REQUESTED_SUITE=basics
assert_selection "" startup EVENT_NAME=workflow_dispatch REQUESTED_SUITE=startup
assert_selection "" recovery-password EVENT_NAME=workflow_dispatch REQUESTED_SUITE=recovery-password

# Test actual revision selection without changing the checkout under review.
git init -q "$temp_dir/repo"
cd "$temp_dir/repo"
git config user.name Fixture
git config user.email fixture@example.org
git -c commit.gpgsign=false commit -qm baseline --allow-empty
export BASE_SHA=$(git rev-parse HEAD)
mkdir -p maestro/auth/online maestro/auth/offline .github/workflows
touch maestro/auth/online/prepared-logout.yaml
git add .
git -c commit.gpgsign=false commit -qm online
export HEAD_SHA=$(git rev-parse HEAD)
assert_selection "" data-sync EVENT_NAME=pull_request
assert_selection "" "$all_online" EVENT_NAME=push

touch maestro/auth/offline/settings.yaml
git add .
git -c commit.gpgsign=false commit -qm offline
export HEAD_SHA=$(git rev-parse HEAD)
assert_selection basics data-sync EVENT_NAME=pull_request
assert_selection "$all_offline" "$all_online" EVENT_NAME=push

export BASE_SHA=$HEAD_SHA
touch README.md
git add .
git -c commit.gpgsign=false commit -qm docs
export HEAD_SHA=$(git rev-parse HEAD)
assert_selection "" "" EVENT_NAME=pull_request
assert_selection "" "" EVENT_NAME=push

touch .github/workflows/auth-android.yml
git add .
git -c commit.gpgsign=false commit -qm workflow
export HEAD_SHA=$(git rev-parse HEAD)
assert_selection "$all_offline" "$all_online" EVENT_NAME=pull_request
assert_selection "$all_offline" "$all_online" EVENT_NAME=push BASE_SHA=0000000000000000000000000000000000000000

if EVENT_NAME=pull_request BASE_SHA=missing "$root/.github/scripts/select-auth-tests.sh" 2>/dev/null; then
    echo "An invalid revision must fail, not skip tests" >&2
    exit 1
fi
if EVENT_NAME=workflow_dispatch REQUESTED_SUITE=typo "$root/.github/scripts/select-auth-tests.sh" 2>/dev/null; then
    echo "An unknown manual suite must fail" >&2
    exit 1
fi

echo "Auth workflow selection tests passed"
