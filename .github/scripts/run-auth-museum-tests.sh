#!/usr/bin/env bash

set -euo pipefail

mkdir -p artifacts/maestro/museum-debug
adb shell settings put system screen_off_timeout 2147483647
adb install -r "$AUTH_APK_PATH"
maestro test --no-ansi \
    --format JUNIT \
    --output artifacts/maestro/museum-results.xml \
    --debug-output artifacts/maestro/museum-debug \
    --flatten-debug-output \
    -e APP_ID="$APP_ID" \
    -e MUSEUM_ENDPOINT="$MUSEUM_ENDPOINT" \
    -e MUSEUM_OTT="$MUSEUM_OTT" \
    -e MISSING_EMAIL="$MISSING_EMAIL" \
    -e ONLINE_EMAIL="$ONLINE_EMAIL" \
    -e ONLINE_PASSWORD="$ONLINE_PASSWORD" \
    maestro/auth/online/museum-unknown-login.yaml \
    maestro/auth/online/museum-signup-recovery-login.yaml
