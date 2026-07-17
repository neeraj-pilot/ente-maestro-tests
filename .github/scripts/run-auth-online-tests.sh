#!/usr/bin/env bash

set -euo pipefail

credentials=museum/fixtures/public-test-credentials.json
fixture_basic_email=$(jq --raw-output '.accounts.basic.email' "$credentials")
fixture_basic_password=$(jq --raw-output '.accounts.basic.password' "$credentials")
fixture_totp_email=$(jq --raw-output '.accounts.totp.email' "$credentials")
fixture_totp_password=$(jq --raw-output '.accounts.totp.password' "$credentials")
fixture_totp_secret=$(jq --raw-output '.accounts.totp.totpSecret' "$credentials")
fixture_recovery_email=$(jq --raw-output '.accounts.recovery.email' "$credentials")
fixture_recovery_password=$(jq --raw-output '.accounts.recovery.password' "$credentials")
fixture_recovery_key=$(jq --raw-output '.accounts.recovery.recoveryKey' "$credentials")
fixture_recovered_password=$(jq --raw-output '.accounts.recovery.recoveredPassword' "$credentials")

mkdir -p artifacts/maestro/online-debug artifacts/maestro/online-results
adb shell settings put system screen_off_timeout 2147483647
adb install -r "$AUTH_APK_PATH"

run_maestro() {
    local result_name=$1
    shift
    maestro test --no-ansi \
        --format JUNIT \
        --output "artifacts/maestro/online-results/$result_name.xml" \
        --debug-output "artifacts/maestro/online-debug/$result_name" \
        --flatten-debug-output \
        -e APP_ID="$APP_ID" \
        -e ONLINE_ENDPOINT="$ONLINE_ENDPOINT" \
        "$@"
}

run_maestro prepared-password \
    -e FIXTURE_BASIC_EMAIL="$fixture_basic_email" \
    -e FIXTURE_BASIC_PASSWORD="$fixture_basic_password" \
    maestro/auth/online/prepared-password-login.yaml

run_maestro prepared-totp-start \
    -e FIXTURE_TOTP_EMAIL="$fixture_totp_email" \
    -e FIXTURE_TOTP_PASSWORD="$fixture_totp_password" \
    maestro/auth/online/prepared-totp-login-start.yaml
fixture_totp_code=$(TOTP_SECRET="$fixture_totp_secret" node scripts/current-totp.mjs)
run_maestro prepared-totp-complete \
    -e FIXTURE_TOTP_CODE="$fixture_totp_code" \
    maestro/auth/online/prepared-totp-login-complete.yaml

run_maestro signup-and-errors \
    -e ONLINE_OTT="$ONLINE_OTT" \
    -e MISSING_EMAIL="$MISSING_EMAIL" \
    -e ONLINE_EMAIL="$ONLINE_EMAIL" \
    -e ONLINE_PASSWORD="$ONLINE_PASSWORD" \
    maestro/auth/online/unknown-login.yaml \
    maestro/auth/online/signup-recovery-login.yaml \
    maestro/auth/online/password-login.yaml

run_maestro prepared-recovery \
    -e ONLINE_OTT="$ONLINE_OTT" \
    -e FIXTURE_RECOVERY_EMAIL="$fixture_recovery_email" \
    -e FIXTURE_RECOVERY_PASSWORD="$fixture_recovery_password" \
    -e FIXTURE_RECOVERY_KEY="$fixture_recovery_key" \
    -e FIXTURE_RECOVERED_PASSWORD="$fixture_recovered_password" \
    maestro/auth/online/prepared-recovery-password-reset.yaml
