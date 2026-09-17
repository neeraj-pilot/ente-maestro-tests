#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
mkdir -p "$temp_dir/bin"
export PATH="$temp_dir/bin:$PATH"
export MOCK_CALLS="$temp_dir/calls"
export MAESTRO_ARTIFACTS_DIR="$temp_dir/runs"

touch "$temp_dir/auth.apk"

# No device is touched by these host-runner checks.
if grep -RL '^appId: ${APP_ID}$' "$root/maestro/auth" --include='*.yaml' --exclude='config.yaml' | grep -q .; then
    echo "Every Auth flow must honor the runner's APP_ID" >&2
    exit 1
fi
cat > "$temp_dir/bin/adb" <<'SH'
#!/usr/bin/env bash
[[ "$1" != -s ]] || shift 2
if [[ -n ${MOCK_DEVICE_CALLS:-} ]]; then printf '%s\n' "$*" >> "$MOCK_DEVICE_CALLS"; fi
case "$*" in
    install*) exit "${MOCK_INSTALL_STATUS:-0}" ;;
    get-state) echo device ;;
    'shell true') exit "${MOCK_DEVICE_STATUS:-0}" ;;
    'shell dumpsys connectivity')
        echo check >> "$MOCK_NETWORK_CALLS"
        case ${MOCK_NETWORK_MODE:-} in
            absent) echo 'Active default network: none'; exit ;;
            delayed)
                if [[ $(wc -l < "$MOCK_NETWORK_CALLS") -lt 3 ]]; then
                    echo 'Active default network: none'
                    exit
                fi
                ;;
        esac
        echo 'Active default network: 101'
        [[ ${MOCK_NETWORK_MODE:-} != failed-command ]] || exit 29
        ;;
    'shell id -u'|'shell am get-current-user') echo 0 ;;
    'shell stat '*) echo 1000:1000 ;;
    'shell pidof '*) echo 123 ;;
    'shell dumpsys meminfo '*) echo fixture-memory-info ;;
esac
SH
cat > "$temp_dir/bin/maestro" <<'SH'
#!/usr/bin/env bash
[[ "$MAESTRO_CLI_NO_ANALYTICS" == 1 && "$MAESTRO_API_URL" == http://127.0.0.1:9 ]] || exit 1
if [[ "$1" == --version ]]; then
    echo 2.10.0
else
    printf '%s\n' "$@" >> "$MOCK_CALLS"
    [[ ${MOCK_MAESTRO_MODE:-} != fail ]] || exit 42
    for argument in "$@"; do
        if [[ "$argument" == "${MOCK_FAIL_FLOW:-}" ]]; then exit 42; fi
    done
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == --output ]]; then report=$2; break; fi
        shift
    done
    case ${MOCK_MAESTRO_MODE:-} in
        missing) ;;
        empty) : > "$report" ;;
        *) printf '<testsuite tests="1" failures="0"><testcase name="fixture"/></testsuite>\n' > "$report" ;;
    esac
fi
SH
chmod +x "$temp_dir/bin/adb" "$temp_dir/bin/maestro"
# Selection is delegated to Maestro; this runner installs once and invokes it once.
ANDROID_SERIAL=fixture-device AUTH_APK_PATH="$temp_dir/auth.apk" \
    "$root/scripts/run-auth-offline.sh"
grep -Fxq 'maestro/auth' "$MOCK_CALLS"
grep -Fxq 'basics,organization,tags,trash' "$MOCK_CALLS"

: > "$MOCK_CALLS"
MOCK_DEVICE_CALLS="$temp_dir/device-calls" \
    ANDROID_SERIAL=fixture-device AUTH_APK_PATH="$temp_dir/auth.apk" \
    "$root/scripts/run-auth-offline.sh" basics trash
grep -Fxq 'basics,trash' "$MOCK_CALLS"
[[ $(grep -c '^install ' "$temp_dir/device-calls") -eq 1 ]]
[[ $(grep -c '^maestro/auth$' "$MOCK_CALLS") -eq 1 ]]

: > "$MOCK_CALLS"
status=0
MOCK_INSTALL_STATUS=17 ANDROID_SERIAL=fixture-device AUTH_APK_PATH="$temp_dir/auth.apk" \
    "$root/scripts/run-auth-offline.sh" basics trash || status=$?
[[ $status -eq 17 && ! -s "$MOCK_CALLS" ]]

for mode in fail missing empty disconnected; do
    status=0
    device_status=0
    expected=1
    case "$mode" in
        fail) expected=42 ;;
        disconnected) device_status=23; expected=23 ;;
    esac
    MOCK_MAESTRO_MODE="$mode" MOCK_DEVICE_STATUS="$device_status" \
        ANDROID_SERIAL=fixture-device AUTH_APK_PATH="$temp_dir/auth.apk" \
        "$root/scripts/run-auth-offline.sh" basics \
        > /dev/null 2> "$temp_dir/error" || status=$?
    [[ $status -eq $expected ]]
    if [[ "$mode" == missing || "$mode" == empty ]]; then
        grep -Fq 'nonempty JUnit report' "$temp_dir/error"
    fi
done

# Exercise the actual online runner under the host's system Bash (3.2 on macOS).

cat > "$temp_dir/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$temp_dir/bin/sleep"
cat > "$temp_dir/bin/curl" <<'SH'
#!/usr/bin/env bash
echo '{"id":"0137a0c754ac0fe4f2c4c7421727c349327eb990"}'
SH
chmod +x "$temp_dir/bin/curl"
cat > "$temp_dir/bin/docker" <<'SH'
#!/usr/bin/env bash
case "$*" in
    *'up --wait'*) exit "${MOCK_START_STATUS:-0}" ;;
    *pg_restore*)
        echo restore >> "$MOCK_BACKEND_CALLS"
        exit "${MOCK_RESTORE_STATUS:-0}"
        ;;
    *"source = 'authMaestroFixture'"*) echo '3|3|1|3|5|0' ;;
    *'SELECT COUNT(*), MAX(updated_at)'*) echo '4|11' ;;
    *'SELECT MAX(user_id)'*) echo 3 ;;
    *'SELECT MAX(updated_at)'*) echo 10 ;;
    *'SELECT COUNT(*)'*|*'SELECT (SELECT COUNT(*)'*)
        echo check >> "$MOCK_DATABASE_CALLS"
        if [[ ${MOCK_DATABASE_MODE:-} == absent ]] ||
            [[ ${MOCK_DATABASE_MODE:-} == delayed && $(wc -l < "$MOCK_DATABASE_CALLS") -lt 3 ]]; then
            echo f
        else
            echo t
        fi
        ;;
    *logs*) echo fixture-backend-log ;;
esac
SH
chmod +x "$temp_dir/bin/docker"

run_online() (
    name=$1
    shift
    cd "$root"
    : > "$MOCK_CALLS"
    export MOCK_NETWORK_CALLS="$temp_dir/network-calls"
    : > "$MOCK_NETWORK_CALLS"
    export MOCK_DATABASE_CALLS="$temp_dir/database-calls"
    : > "$MOCK_DATABASE_CALLS"
    export MOCK_BACKEND_CALLS="$temp_dir/backend-calls"
    : > "$MOCK_BACKEND_CALLS"
    export MOCK_DEVICE_CALLS="$temp_dir/online-device-calls"
    : > "$MOCK_DEVICE_CALLS"
    read -r -a suites <<< "${MOCK_ONLINE_SUITES:-recovery-password}"
    set -- "$@" /bin/bash scripts/run-auth-online.sh
    if [[ ${MOCK_ONLINE_SUITES:-} != all ]]; then set -- "$@" "${suites[@]}"; fi
    env -u ANDROID_SERIAL -u MAESTRO_DEVICE -u ONLINE_ENDPOINT -u APP_ID \
        GITHUB_ACTIONS=true AUTH_APP_PREPARATION=root-prefs \
        AUTH_APK_PATH="$temp_dir/auth.apk" \
        AUTH_FIXTURE_COMPOSE_PROJECT=mock-backend \
        MAESTRO_ARTIFACTS_DIR="$temp_dir/online-$name" \
        "$@"
)

run_online automatic ONLINE_ENDPOINT=http://10.0.2.2:8080
grep -Fxq 'maestro/auth/online/recovery/reset-password.yaml' "$MOCK_CALLS"
if grep -Fxq -- '--device' "$MOCK_CALLS"; then
    echo "Automatic device selection must not pass --device" >&2
    exit 1
fi
run_online selected ONLINE_ENDPOINT=http://10.0.2.2:8080 ANDROID_SERIAL=fixture-device
[[ $(sed -n '/^--device$/{n;p;}' "$MOCK_CALLS" | sort -u) == fixture-device ]]

# Local runs use UI preparation and loopback Museum without CI environment values.
run_online local AUTH_APP_PREPARATION=ui
[[ $(grep -c '^maestro/auth/online/subflows/configure-online-test-endpoint-ui.yaml$' "$MOCK_CALLS") -eq 3 ]]
[[ $(grep -E '^maestro/.*\.yaml$' "$MOCK_CALLS" | grep -v '/subflows/') == $'maestro/auth/online/recovery/reset-password.yaml\nmaestro/auth/online/recovery/old-password.yaml\nmaestro/auth/online/recovery/login.yaml' ]]
grep -Fxq 'APP_ID=io.ente.auth.independent' "$MOCK_CALLS"
grep -Fxq 'ONLINE_ENDPOINT=http://127.0.0.1:8080' "$MOCK_CALLS"
grep -Fxq 'ONLINE_OTT=123456' "$MOCK_CALLS"

MOCK_ONLINE_SUITES=recovery-password run_online recovery
[[ $(grep -E '^maestro/.*\.yaml$' "$MOCK_CALLS") == $'maestro/auth/online/recovery/reset-password.yaml\nmaestro/auth/online/recovery/old-password.yaml\nmaestro/auth/online/recovery/login.yaml' ]]

MOCK_ONLINE_SUITES=account-auth run_online signup TOTP_TIME=60 > "$temp_dir/signup-log"
[[ $(grep -c '^ONLINE_EMAIL=auth-maestro-signup-fixture-[a-f0-9]*@example.org$' "$MOCK_CALLS") -eq 2 ]]
[[ $(grep '^ONLINE_EMAIL=' "$MOCK_CALLS" | sort -u | wc -l) -eq 1 ]]
[[ $(grep -c '^ONLINE_PASSWORD=AuthCi-[a-f0-9]*!$' "$MOCK_CALLS") -eq 2 ]]
[[ $(grep '^ONLINE_PASSWORD=' "$MOCK_CALLS" | sort -u | wc -l) -eq 1 ]]
grep -Fxq "::add-mask::$(sed -n 's/^ONLINE_PASSWORD=//p' "$MOCK_CALLS" | head -1)" "$temp_dir/signup-log"

MOCK_ONLINE_SUITES=data-sync run_online sync-delayed MOCK_DATABASE_MODE=delayed
[[ $(wc -l < "$temp_dir/database-calls") -eq 3 ]]
grep -Fxq 'maestro/auth/online/sync/relogin.yaml' "$MOCK_CALLS"
status=0
MOCK_ONLINE_SUITES=data-sync run_online sync-absent MOCK_DATABASE_MODE=absent \
    2> "$temp_dir/error" || status=$?
[[ $status -eq 1 && $(wc -l < "$temp_dir/database-calls") -eq 60 ]]
grep -Fq 'Timed out waiting for database condition:' "$temp_dir/error"
if grep -Fxq 'maestro/auth/online/sync/relogin.yaml' "$MOCK_CALLS"; then
    echo "Fresh login must wait for the app's mutation to reach Museum" >&2
    exit 1
fi

run_online network-delayed ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_NETWORK_MODE=delayed
[[ $(wc -l < "$temp_dir/network-calls") -eq 5 ]]
grep -Fxq 'maestro/auth/online/recovery/reset-password.yaml' "$MOCK_CALLS"
for mode in absent failed-command; do
    status=0
    run_online "network-$mode" ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_NETWORK_MODE="$mode" \
        2> "$temp_dir/error" || status=$?
    [[ $status -eq 1 && ! -s "$MOCK_CALLS" ]]
    grep -Fq 'Android has no active default network' "$temp_dir/error"
    grep -Fq 'Active default network:' "$temp_dir/online-network-$mode/runtime-health/recovery-password-device.txt"
done

status=0
run_online disconnected ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_DEVICE_STATUS=23 || status=$?
[[ $status -eq 23 ]]
grep -Fxq 'fixture-memory-info' "$temp_dir/online-disconnected/runtime-health/recovery-password-device.txt"
grep -Fxq 'fixture-backend-log' "$temp_dir/online-disconnected/runtime-health/recovery-password-backend.log"

for mode in fail missing empty; do
    status=0
    run_online "$mode" ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_MAESTRO_MODE="$mode" \
        2> "$temp_dir/error" || status=$?
    expected=1
    if [[ "$mode" == fail ]]; then expected=42; fi
    [[ $status -eq $expected ]]
    if [[ "$mode" != fail ]]; then grep -Fq 'nonempty JUnit report' "$temp_dir/error"; fi
    grep -Fxq 'fixture-memory-info' "$temp_dir/online-$mode/runtime-health/recovery-password-device.txt"
done

# Suites share one installation, but each gets a clean backend. A failed phase
# stops its dependent steps without suppressing the next independent suite.
MOCK_ONLINE_SUITES=all run_online all TOTP_TIME=60
[[ $(grep -c '^install ' "$temp_dir/online-device-calls") -eq 1 ]]
[[ $(wc -l < "$temp_dir/backend-calls") -eq 4 ]]
[[ $(find "$temp_dir/online-all/results" -name '*.xml' | wc -l) -eq 17 ]]

status=0
MOCK_ONLINE_SUITES="recovery-password data-sync" run_online combined \
    MOCK_FAIL_FLOW=maestro/auth/online/recovery/reset-password.yaml || status=$?
[[ $status -eq 42 ]]
[[ $(grep -c '^install ' "$temp_dir/online-device-calls") -eq 1 ]]
[[ $(wc -l < "$temp_dir/backend-calls") -eq 2 ]]
grep -Fxq 'maestro/auth/online/sync/logout.yaml' "$MOCK_CALLS"
if grep -Fxq 'maestro/auth/online/recovery/old-password.yaml' "$MOCK_CALLS"; then
    echo "Recovery verification must not run after a failed reset" >&2
    exit 1
fi

status=0
run_online backend-unhealthy MOCK_START_STATUS=27 || status=$?
[[ $status -eq 27 && ! -s "$MOCK_CALLS" && ! -s "$temp_dir/backend-calls" ]]

status=0
run_online restore-failure MOCK_RESTORE_STATUS=31 || status=$?
[[ $status -eq 31 && ! -s "$MOCK_CALLS" ]]

# Missing required input must fail before touching Maestro.
status=0
run_online missing-apk AUTH_APK_PATH= 2> "$temp_dir/error" || status=$?
[[ $status -ne 0 ]]
grep -Fq 'Set AUTH_APK_PATH to the Auth nightly APK' "$temp_dir/error"
[[ ! -s "$MOCK_CALLS" ]]

echo "CI helper, local suite parity and failure diagnostics tests passed"
