#!/usr/bin/env bash

set -euo pipefail

lane=${1:-all}
: "${FIXTURE_MUTATION_TAG:=FixturePersisted}"
: "${ONLINE_CODE_ACCOUNT:=first-key-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}@example.org}"
credentials=museum/fixtures/public-test-credentials.json
fixture_basic_email=$(jq --raw-output '.accounts.basic.email' "$credentials")
fixture_basic_password=$(jq --raw-output '.accounts.basic.password' "$credentials")
fixture_basic_user_id=$(jq --raw-output '.accounts.basic.userId' "$credentials")
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
    local maestro_device_args=()
    shift
    if [[ -n ${MAESTRO_DEVICE:-} ]]; then
        maestro_device_args=(--device "$MAESTRO_DEVICE")
    fi
    maestro test --no-ansi \
        "${maestro_device_args[@]}" \
        --format JUNIT \
        --output "artifacts/maestro/online-results/$result_name.xml" \
        --debug-output "artifacts/maestro/online-debug/$result_name" \
        --flatten-debug-output \
        -e APP_ID="$APP_ID" \
        -e ONLINE_ENDPOINT="$ONLINE_ENDPOINT" \
        "$@"
}

prepare_basic_fixture_app() {
    local app_data_dir app_owner current_user preferences_dir preferences_file

    adb root >/dev/null
    adb wait-for-device
    if [[ $(adb shell id -u | tr -d '\r') != 0 ]]; then
        echo "Prepared Auth fixture logins require a rootable Android emulator" >&2
        return 1
    fi

    current_user=$(adb shell am get-current-user | tr -d '\r')
    app_data_dir="/data/user/$current_user/$APP_ID"
    preferences_dir="$app_data_dir/shared_prefs"
    preferences_file="$preferences_dir/FlutterSharedPreferences.xml"
    adb shell pm clear "$APP_ID" >/dev/null
    app_owner=$(adb shell stat -c '%u:%g' "$app_data_dir" | tr -d '\r')
    if [[ ! "$app_owner" =~ ^[0-9]+:[0-9]+$ ]]; then
        echo "Unable to determine the Auth app-data owner: $app_owner" >&2
        return 1
    fi

    adb shell "mkdir -p '$preferences_dir'"
    adb shell \
        "printf '%s\\n' '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?>' '<map>' '    <boolean name=\"flutter.has_shown_coach_mark_v2\" value=\"true\" />' '</map>' > '$preferences_file'"
    adb shell chown -R "$app_owner" "$preferences_dir"
    adb shell chmod 771 "$preferences_dir"
    adb shell chmod 660 "$preferences_file"
    adb shell restorecon "$preferences_dir"
    adb shell restorecon "$preferences_file"
    if ! adb shell \
        "grep -q 'name=\"flutter.has_shown_coach_mark_v2\" value=\"true\"' '$preferences_file'"; then
        echo "Unable to preseed the Auth code guidance preference" >&2
        return 1
    fi
}

query_fixture_db() {
    local query=$1
    docker compose \
        --project-name "$AUTH_FIXTURE_COMPOSE_PROJECT" \
        --file museum/compose.yaml \
        exec -T postgres \
        psql --tuples-only --no-align --field-separator='|' \
        --username=ente_auth --dbname=ente_auth_test \
        --command="$query"
}

wait_for_first_auth_entity() {
    local previous_max_user_id=$1
    local state
    for _ in {1..60}; do
        state=$(query_fixture_db \
            "SELECT (SELECT COUNT(*) FROM authenticator_key WHERE user_id > $previous_max_user_id), (SELECT COUNT(*) FROM authenticator_entity WHERE user_id > $previous_max_user_id);")
        if [[ "$state" == "1|1" ]]; then
            return
        fi
        sleep 1
    done
    echo "Timed out waiting for the new account's first Auth key and entity; last state: $state" >&2
    return 1
}

wait_for_bulk_mutation() {
    local user_id=$1
    local previous_marker=$2
    local updated_count
    for _ in {1..60}; do
        updated_count=$(query_fixture_db \
            "SELECT COUNT(*) FROM authenticator_entity WHERE user_id = $user_id AND updated_at > $previous_marker;")
        if [[ "$updated_count" -ge 2 ]]; then
            return
        fi
        sleep 1
    done
    echo "Timed out waiting for two persisted Auth mutations for fixture user $user_id; observed: $updated_count" >&2
    return 1
}

run_account_auth() {
    local fixture_totp_code previous_max_user_id

    run_maestro prepared-totp-start \
        -e FIXTURE_TOTP_EMAIL="$fixture_totp_email" \
        -e FIXTURE_TOTP_PASSWORD="$fixture_totp_password" \
        maestro/auth/online/prepared-totp-login-start.yaml
    fixture_totp_code=$(
        TOTP_SECRET="$fixture_totp_secret" \
            TOTP_MIN_VALIDITY_SECONDS=20 \
            node scripts/current-totp.mjs
    )
    run_maestro prepared-totp-complete \
        -e FIXTURE_TOTP_CODE="$fixture_totp_code" \
        maestro/auth/online/prepared-totp-login-complete.yaml
    run_maestro unknown-login \
        -e MISSING_EMAIL="$MISSING_EMAIL" \
        maestro/auth/online/unknown-login.yaml
    previous_max_user_id=$(query_fixture_db "SELECT MAX(user_id) FROM users;")
    run_maestro signup-first-key \
        -e ONLINE_OTT="$ONLINE_OTT" \
        -e ONLINE_EMAIL="$ONLINE_EMAIL" \
        -e ONLINE_PASSWORD="$ONLINE_PASSWORD" \
        -e ONLINE_CODE_ACCOUNT="$ONLINE_CODE_ACCOUNT" \
        maestro/auth/online/signup-recovery-login.yaml
    wait_for_first_auth_entity "$previous_max_user_id"
    run_maestro signup-cold-login \
        -e ONLINE_EMAIL="$ONLINE_EMAIL" \
        -e ONLINE_PASSWORD="$ONLINE_PASSWORD" \
        -e ONLINE_CODE_ACCOUNT="$ONLINE_CODE_ACCOUNT" \
        maestro/auth/online/password-login.yaml
}

run_recovery_password() {
    run_maestro prepared-recovery \
        -e ONLINE_OTT="$ONLINE_OTT" \
        -e FIXTURE_RECOVERY_EMAIL="$fixture_recovery_email" \
        -e FIXTURE_RECOVERY_PASSWORD="$fixture_recovery_password" \
        -e FIXTURE_RECOVERY_KEY="$fixture_recovery_key" \
        -e FIXTURE_RECOVERED_PASSWORD="$fixture_recovered_password" \
        maestro/auth/online/prepared-recovery-password-reset.yaml
}

run_data_sync() {
    local mutation_marker

    prepare_basic_fixture_app
    run_maestro prepared-password \
        -e FIXTURE_BASIC_EMAIL="$fixture_basic_email" \
        -e FIXTURE_BASIC_PASSWORD="$fixture_basic_password" \
        maestro/auth/online/prepared-password-login.yaml

    mutation_marker=$(query_fixture_db \
        "SELECT MAX(updated_at) FROM authenticator_entity WHERE user_id = $fixture_basic_user_id;")
    run_maestro prepared-bulk-mutation-start \
        -e FIXTURE_MUTATION_TAG="$FIXTURE_MUTATION_TAG" \
        maestro/auth/online/prepared-bulk-mutation-start.yaml
    wait_for_bulk_mutation "$fixture_basic_user_id" "$mutation_marker"
    prepare_basic_fixture_app
    run_maestro prepared-bulk-mutation-complete \
        -e FIXTURE_BASIC_EMAIL="$fixture_basic_email" \
        -e FIXTURE_BASIC_PASSWORD="$fixture_basic_password" \
        -e FIXTURE_MUTATION_TAG="$FIXTURE_MUTATION_TAG" \
        maestro/auth/online/prepared-bulk-mutation-complete.yaml
}

case "$lane" in
    account-auth) run_account_auth ;;
    recovery-password) run_recovery_password ;;
    data-sync) run_data_sync ;;
    all)
        run_account_auth
        run_recovery_password
        run_data_sync
        ;;
    *)
        echo "Unknown Auth online test lane: $lane" >&2
        exit 2
        ;;
esac
