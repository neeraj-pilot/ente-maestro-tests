#!/usr/bin/env bash

set -euo pipefail

mkdir -p artifacts/maestro/online-debug
adb shell settings put system screen_off_timeout 2147483647
adb install -r "$AUTH_APK_PATH"
{
    adb shell wm size
    adb shell wm density
    adb shell settings get system font_scale
} > artifacts/maestro/device-metrics.txt
test_status=0
maestro test --no-ansi \
    --format JUNIT \
    --output artifacts/maestro/online-results.xml \
    --debug-output artifacts/maestro/online-debug \
    --flatten-debug-output \
    -e APP_ID="$APP_ID" \
    -e ONLINE_ENDPOINT="$ONLINE_ENDPOINT" \
    -e ONLINE_OTT="$ONLINE_OTT" \
    -e MISSING_EMAIL="$MISSING_EMAIL" \
    -e ONLINE_EMAIL="$ONLINE_EMAIL" \
    -e ONLINE_PASSWORD="$ONLINE_PASSWORD" \
    maestro/auth/online/unknown-login.yaml \
    maestro/auth/online/signup-recovery-login.yaml || test_status=$?

if ((test_status != 0)); then
    adb shell uiautomator dump /sdcard/auth-window.xml >/dev/null 2>&1 || true
    adb shell cat /sdcard/auth-window.xml 2>/dev/null \
        | grep -E 'text="(Account|Change email|Change password|Recovery key|Logout|Delete)"' \
        > artifacts/maestro/account-settings-hierarchy.txt || true
    timeout 15s maestro hierarchy --compact --no-ansi 2>/dev/null \
        | grep -E '(Account|Change email|Change password|Recovery key|Logout|Delete account)' \
        > artifacts/maestro/maestro-account-hierarchy.txt || true
fi

exit "$test_status"
