#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly runner="$workspace_root/.github/scripts/run-auth-online-tests.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/bin"
cat > "$temp_dir/bin/adb" <<'EOF'
#!/usr/bin/env bash

if [[ ${1:-} == "get-state" ]]; then
    if [[ ${TEST_ADB_STATE:-device} == "device" ]]; then
        echo "device"
        exit 0
    fi
    exit 1
fi
exit 0
EOF
chmod +x "$temp_dir/bin/adb"

run_failure() {
    local adb_state=$1
    local attempt=$2
    local expected_marker=$3
    local marker="$temp_dir/artifacts/runtime-health/invalid-attempt-${attempt}-emulator-lost"
    local status

    set +e
    PATH="$temp_dir/bin:$PATH" \
        TEST_ADB_STATE="$adb_state" \
        EMULATOR_ATTEMPT="$attempt" \
        MAESTRO_ARTIFACTS_DIR="$temp_dir/artifacts" \
        AUTH_APK_PATH="$temp_dir/auth.apk" \
        APP_ID=io.ente.auth.independent \
        ONLINE_ENDPOINT=http://127.0.0.1 \
        "$runner" invalid > /dev/null 2>&1
    status=$?
    set -e

    if [[ $status -ne 2 ]]; then
        echo "Expected the invalid test lane to exit 2, got $status" >&2
        exit 1
    fi
    if [[ "$expected_marker" == "present" && ! -f "$marker" ]]; then
        echo "Missing emulator-loss marker for unavailable ADB" >&2
        exit 1
    fi
    if [[ "$expected_marker" == "absent" && -e "$marker" ]]; then
        echo "Unexpected emulator-loss marker for a reachable emulator" >&2
        exit 1
    fi
}

run_failure unavailable 1 present
run_failure device 2 absent

echo "Auth online emulator-loss classification tests passed"
