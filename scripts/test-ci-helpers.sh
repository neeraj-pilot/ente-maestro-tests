#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
mkdir -p "$temp_dir/bin"
export PATH="$temp_dir/bin:$PATH"
export MOCK_CALLS="$temp_dir/calls"
export MAESTRO_ARTIFACTS_DIR="$temp_dir/runs"

cat > "$temp_dir/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_CALLS"
case "$DOWNLOAD_MODE" in
    fail) exit 1 ;;
    retry) [[ $(wc -l < "$MOCK_CALLS") -gt 1 ]] || exit 1 ;;
esac
printf 'fixture APK'
SH
cat > "$temp_dir/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$temp_dir/bin/gh" "$temp_dir/bin/sleep"
digest=$(printf 'fixture APK' | shasum -a 256 | awk '{print $1}')

export DOWNLOAD_MODE=success
"$root/scripts/download-auth-apk.sh" ente/nightly 123 "sha256:$digest" "$temp_dir/auth.apk"
grep -Fx 'api -H Accept: application/octet-stream repos/ente/nightly/releases/assets/123' "$MOCK_CALLS"
[[ $(shasum -a 256 "$temp_dir/auth.apk" | awk '{print $1}') == "$digest" ]]

if "$root/scripts/download-auth-apk.sh" ente/nightly 123 wrong-digest "$temp_dir/auth.apk" 2> "$temp_dir/error"; then
    echo "A mismatched APK digest must fail" >&2
    exit 1
fi
grep -F 'does not match' "$temp_dir/error"

export DOWNLOAD_MODE=retry
: > "$MOCK_CALLS"
"$root/scripts/download-auth-apk.sh" ente/nightly 123 "$digest" "$temp_dir/auth.apk"
[[ $(wc -l < "$MOCK_CALLS") -eq 2 ]]

export DOWNLOAD_MODE=fail
: > "$MOCK_CALLS"
if "$root/scripts/download-auth-apk.sh" ente/nightly 123 "$digest" "$temp_dir/auth.apk"; then
    echo "An exhausted download must fail" >&2
    exit 1
fi
[[ $(wc -l < "$MOCK_CALLS") -eq 3 ]]

# Local and hosted runs must resolve the same flow lists. No device is touched.
if grep -RL '^appId: ${APP_ID}$' "$root/maestro/auth" --include='*.yaml' | grep -q .; then
    echo "Every Auth flow must honor the runner's APP_ID" >&2
    exit 1
fi
cat > "$temp_dir/bin/adb" <<'SH'
#!/usr/bin/env bash
[[ "$*" != *get-state ]] || echo device
exit 0
SH
cat > "$temp_dir/bin/maestro" <<'SH'
#!/usr/bin/env bash
[[ "$MAESTRO_CLI_NO_ANALYTICS" == 1 && "$MAESTRO_API_URL" == http://127.0.0.1:9 ]] || exit 1
if [[ "$1" == --version ]]; then
    echo 2.10.0
else
    printf '%s\n' "$@" | sed -n '/^maestro\/.*\.yaml$/p' > "$MOCK_CALLS"
fi
SH
chmod +x "$temp_dir/bin/adb" "$temp_dir/bin/maestro"
for suite in setup organization settings tags trash required setup; do
    "$root/scripts/run-auth-android-local.sh" --serial fixture-device \
        --apk "$temp_dir/auth.apk" --skip-install --suite "$suite"
    if [[ "$suite" == required ]]; then
        matrix=$("$root/scripts/select-auth-ci-suites.sh" --all)
    else
        matrix=$("$root/scripts/select-auth-ci-suites.sh" --suite "$suite")
    fi
    expected=$(jq -r '.include[].flows | split(" ")[]' <<< "$matrix")
    [[ $(< "$MOCK_CALLS") == "$expected" ]]
done

[[ $(find "$temp_dir/runs" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 7 ]]

# A failing device command retains its status and captures health before teardown.
cat > "$temp_dir/bin/adb" <<'SH'
#!/usr/bin/env bash
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
        .github/scripts/run-auth-online-tests.sh data-sync
) || status=$?
[[ $status -eq 37 ]]
grep -Fx 'fixture-memory-info' "$temp_dir"/diagnostics/data-sync-*/runtime-health/data-sync-device.txt

# Exercise the actual online runner under the host's system Bash (3.2 on macOS).
cat > "$temp_dir/bin/adb" <<'SH'
#!/usr/bin/env bash
case "$*" in
    'shell id -u'|'shell am get-current-user') echo 0 ;;
    'shell stat '*) echo 1000:1000 ;;
    'shell pidof '*) echo 123 ;;
    'shell dumpsys meminfo '*) echo fixture-memory-info ;;
    'exec-out uiautomator dump /dev/tty') echo '<hierarchy/>' ;;
    'logcat -d') echo fixture-startup-logcat ;;
esac
SH
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
    env -u MAESTRO_DEVICE -u ONLINE_ENDPOINT \
        GITHUB_ACTIONS=true APP_ID=io.ente.auth.independent ONLINE_OTT=123456 \
        AUTH_APK_PATH="$temp_dir/auth.apk" \
        MAESTRO_ARTIFACTS_DIR="$temp_dir/online-$name" \
        "$@" /bin/bash .github/scripts/run-auth-online-tests.sh "${MOCK_ONLINE_PHASE:-recovery-reset}"
)

run_online automatic ONLINE_ENDPOINT=http://10.0.2.2:8080
grep -Fxq 'maestro/auth/online/prepared-recovery-password-reset.yaml' "$MOCK_CALLS"
if grep -Fxq -- '--device' "$MOCK_CALLS"; then
    echo "Automatic device selection must not pass --device" >&2
    exit 1
fi
run_online selected ONLINE_ENDPOINT=http://10.0.2.2:8080 MAESTRO_DEVICE=fixture-device
[[ $(sed -n '/^--device$/{n;p;}' "$MOCK_CALLS") == fixture-device ]]

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
