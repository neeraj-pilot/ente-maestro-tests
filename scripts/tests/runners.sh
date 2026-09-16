#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
mkdir -p "$temp_dir/bin"
export PATH="$temp_dir/bin:$PATH"
export MOCK_CALLS="$temp_dir/calls"
export MAESTRO_ARTIFACTS_DIR="$temp_dir/runs"
# Mock suite results must not appear in the preparation job's real test summary.
unset GITHUB_STEP_SUMMARY

touch "$temp_dir/auth.apk"

# Local and hosted runs must resolve the same flow lists. No device is touched.
if grep -RL '^appId: ${APP_ID}$' "$root/maestro/auth" --include='*.yaml' | grep -q .; then
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
esac
exit 0
SH
cat > "$temp_dir/bin/maestro" <<'SH'
#!/usr/bin/env bash
[[ "$MAESTRO_CLI_NO_ANALYTICS" == 1 && "$MAESTRO_API_URL" == http://127.0.0.1:9 ]] || exit 1
if [[ "$1" == --version ]]; then
    echo 2.10.0
else
    printf '%s\n' "$@" | sed -n '/^maestro\/.*\.yaml$/p' >> "$MOCK_CALLS"
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
for suite in basics organization tags trash required basics; do
    : > "$MOCK_CALLS"
    "$root/scripts/run-auth-android-local.sh" --serial fixture-device \
        --apk "$temp_dir/auth.apk" --skip-install --suite "$suite"
    if [[ "$suite" == required ]]; then
        matrix=$(python3 "$root/scripts/suites.py" --suite offline)
    else
        matrix=$(python3 "$root/scripts/suites.py" --suite "$suite")
    fi
    expected=$(jq -r '.offline.include[].flows[]' <<< "$matrix")
    [[ $(< "$MOCK_CALLS") == "$expected" ]]
done

[[ $(find "$temp_dir/runs" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 6 ]]

# A failed suite must not hide the next suite or trigger another APK installation.
: > "$MOCK_CALLS"
status=0
MOCK_DEVICE_CALLS="$temp_dir/device-calls" \
    MOCK_FAIL_FLOW=maestro/auth/smoke/onboarding.yaml \
    MAESTRO_ARTIFACTS_DIR="$temp_dir/combined" \
    GITHUB_STEP_SUMMARY="$temp_dir/summary" \
    "$root/scripts/run-auth-android-local.sh" --serial fixture-device \
    --apk "$temp_dir/auth.apk" --suite 'basics trash' || status=$?
[[ $status -eq 42 ]]
[[ $(grep -c '^install ' "$temp_dir/device-calls") -eq 1 ]]
selection=$(python3 "$root/scripts/suites.py" --suite offline)
[[ $(< "$MOCK_CALLS") == "$(jq -r '.offline.include[] | select(.suite == "basics" or .suite == "trash") | .flows[]' <<< "$selection")" ]]
grep -Fxq '| basics | failure |' "$temp_dir/summary"
grep -Fxq '| trash | success |' "$temp_dir/summary"
grep -Fq '<testcase' "$temp_dir"/combined/*/trash/results.xml

: > "$MOCK_CALLS"
status=0
MOCK_INSTALL_STATUS=17 "$root/scripts/run-auth-android-local.sh" --serial fixture-device \
    --apk "$temp_dir/auth.apk" --suite 'basics trash' || status=$?
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
        "$root/scripts/run-auth-android-local.sh" --serial fixture-device \
        --apk "$temp_dir/auth.apk" --skip-install --suite basics \
        > /dev/null 2> "$temp_dir/error" || status=$?
    [[ $status -eq $expected ]]
    if [[ "$mode" == missing || "$mode" == empty ]]; then
        grep -Fq 'nonempty JUnit report' "$temp_dir/error"
    fi
done

# A failing device command retains its status and captures health before teardown.
cat > "$temp_dir/bin/adb" <<'SH'
#!/usr/bin/env bash
[[ "$1" != -s ]] || shift 2
case "$*" in
    install*) exit 37 ;;
    get-state) echo device ;;
    'shell pidof '*) echo 123 ;;
    'shell dumpsys meminfo '*) echo fixture-memory-info ;;
esac
SH
status=0
(
    cd "$root"
    GITHUB_ACTIONS=false APP_ID=io.ente.auth.independent AUTH_APK_PATH="$temp_dir/auth.apk" \
        MAESTRO_ARTIFACTS_DIR="$temp_dir/diagnostics" \
        scripts/run-auth-online.sh data-sync
) || status=$?
[[ $status -eq 37 ]]
grep -Fx 'fixture-memory-info' "$temp_dir"/diagnostics/data-sync-*/runtime-health/data-sync-device.txt

# Exercise the actual online runner under the host's system Bash (3.2 on macOS).
cat > "$temp_dir/bin/adb" <<'SH'
#!/usr/bin/env bash
[[ "$1" != -s ]] || shift 2
case "$*" in
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
    'exec-out uiautomator dump /dev/tty') echo '<hierarchy/>' ;;
    'logcat -d') echo fixture-startup-logcat ;;
esac
SH
cat > "$temp_dir/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$temp_dir/bin/sleep"
cat > "$temp_dir/bin/docker" <<'SH'
#!/usr/bin/env bash
echo fixture-backend-log
SH
chmod +x "$temp_dir/bin/docker"
cat > "$temp_dir/bin/maestro" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$MOCK_CALLS"
if [[ ${MOCK_MAESTRO_MODE:-} == fail ]]; then exit 42; fi
while [[ $# -gt 0 ]]; do
    if [[ "$1" == --output ]]; then report=$2; break; fi
    shift
done
case ${MOCK_MAESTRO_MODE:-} in
    missing) ;;
    empty) : > "$report" ;;
    *) printf '<testsuite tests="1" failures="0"><testcase name="fixture"/></testsuite>\n' > "$report" ;;
esac
SH

run_online() (
    name=$1
    shift
    cd "$root"
    : > "$MOCK_CALLS"
    export MOCK_NETWORK_CALLS="$temp_dir/network-calls"
    : > "$MOCK_NETWORK_CALLS"
    env -u MAESTRO_DEVICE -u ONLINE_ENDPOINT \
        GITHUB_ACTIONS=true APP_ID=io.ente.auth.independent ONLINE_OTT=123456 \
        AUTH_APK_PATH="$temp_dir/auth.apk" \
        AUTH_FIXTURE_COMPOSE_PROJECT=mock-backend \
        MAESTRO_ARTIFACTS_DIR="$temp_dir/online-$name" \
        "$@" /bin/bash scripts/run-auth-online.sh "${MOCK_ONLINE_PHASE:-recovery-reset}"
)

run_online automatic ONLINE_ENDPOINT=http://10.0.2.2:8080
grep -Fxq 'maestro/auth/online/prepared-recovery-password-reset.yaml' "$MOCK_CALLS"
if grep -Fxq -- '--device' "$MOCK_CALLS"; then
    echo "Automatic device selection must not pass --device" >&2
    exit 1
fi
run_online selected ONLINE_ENDPOINT=http://10.0.2.2:8080 MAESTRO_DEVICE=fixture-device
[[ $(sed -n '/^--device$/{n;p;}' "$MOCK_CALLS") == fixture-device ]]

run_online network-delayed ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_NETWORK_MODE=delayed
[[ $(wc -l < "$temp_dir/network-calls") -eq 3 ]]
grep -Fxq 'maestro/auth/online/prepared-recovery-password-reset.yaml' "$MOCK_CALLS"
for mode in absent failed-command; do
    status=0
    run_online "network-$mode" ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_NETWORK_MODE="$mode" \
        2> "$temp_dir/error" || status=$?
    [[ $status -eq 1 && ! -s "$MOCK_CALLS" ]]
    grep -Fq 'Android has no active default network' "$temp_dir/error"
    grep -Fq 'Active default network:' "$temp_dir/online-network-$mode/runtime-health/recovery-reset-device.txt"
done

status=0
run_online disconnected ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_DEVICE_STATUS=23 || status=$?
[[ $status -eq 23 ]]
grep -Fxq 'fixture-memory-info' "$temp_dir/online-disconnected/runtime-health/recovery-reset-device.txt"
grep -Fxq 'fixture-backend-log' "$temp_dir/online-disconnected/runtime-health/recovery-reset-backend.log"

MOCK_ONLINE_PHASE=startup run_online startup ONLINE_ENDPOINT=http://10.0.2.2:8080
[[ $(grep -E '^maestro/.*\.yaml$' "$MOCK_CALLS") == maestro/auth/online/startup.yaml ]]
if grep -Eq 'FIXTURE_.*(PASSWORD|EMAIL|CODE|KEY)=' "$MOCK_CALLS"; then
    echo "Startup diagnostics must not receive account credentials" >&2
    exit 1
fi
grep -Fxq '<hierarchy/>' "$temp_dir/online-startup/online-debug/startup/ui-hierarchy.txt"
grep -Fxq 'fixture-startup-logcat' "$temp_dir/online-startup/online-debug/startup/startup-logcat.txt"
status=0
MOCK_ONLINE_PHASE=startup run_online startup-failed ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_MAESTRO_MODE=fail || status=$?
[[ $status -eq 42 ]]
grep -Fxq '<hierarchy/>' "$temp_dir/online-startup-failed/online-debug/startup/ui-hierarchy.txt"

for mode in fail missing empty; do
    status=0
    run_online "$mode" ONLINE_ENDPOINT=http://10.0.2.2:8080 MOCK_MAESTRO_MODE="$mode" \
        2> "$temp_dir/error" || status=$?
    expected=1
    if [[ "$mode" == fail ]]; then expected=42; fi
    [[ $status -eq $expected ]]
    if [[ "$mode" != fail ]]; then grep -Fq 'nonempty JUnit report' "$temp_dir/error"; fi
    grep -Fxq 'fixture-memory-info' "$temp_dir/online-$mode/runtime-health/recovery-reset-device.txt"
done

# A shell expansion error must fail even when Bash 3.2 supplies status 0 to EXIT.
status=0
run_online unbound 2> "$temp_dir/error" || status=$?
[[ $status -ne 0 ]]
grep -Fq 'ONLINE_ENDPOINT: unbound variable' "$temp_dir/error"
[[ ! -s "$MOCK_CALLS" ]]
grep -Fxq 'fixture-memory-info' "$temp_dir/online-unbound/runtime-health/recovery-reset-device.txt"

cat > "$temp_dir/bin/psql" <<'SH'
#!/usr/bin/env bash
echo "$MOCK_DATABASE_STATE"
SH
chmod +x "$temp_dir/bin/psql"
MOCK_DATABASE_STATE='3|3|1|3|5|0' "$root/scripts/fixtures/verify-restored-auth-fixture.sh" psql
if MOCK_DATABASE_STATE='3|3|1|3|4|0' "$root/scripts/fixtures/verify-restored-auth-fixture.sh" psql 2> "$temp_dir/error"; then
    echo "A missing restored code must fail validation" >&2
    exit 1
fi
grep -q 'expected 3|3|1|3|5|0, got 3|3|1|3|4|0' "$temp_dir/error"

echo "CI helper, local suite parity and failure diagnostics tests passed"
