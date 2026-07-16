#!/usr/bin/env bash

set -euo pipefail

mkdir -p artifacts/maestro/online-debug
adb shell settings put system screen_off_timeout 2147483647
adb install -r "$AUTH_APK_PATH"
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
    maestro/auth/online/signup-recovery-login.yaml \
    maestro/auth/online/password-login.yaml
