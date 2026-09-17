#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."
: "${AUTH_APK_PATH:?Set AUTH_APK_PATH to the Auth nightly APK}"
export APP_ID=${APP_ID:-io.ente.auth.independent}
export MAESTRO_DEVICE=${ANDROID_SERIAL:-}
export AUTH_FIXTURE_COMPOSE_PROJECT=${AUTH_FIXTURE_COMPOSE_PROJECT:-ente-auth-fixture}
ONLINE_ENDPOINT=${ONLINE_ENDPOINT:-http://127.0.0.1:8080}
ONLINE_OTT=${ONLINE_OTT:-123456}
if [[ $# -eq 0 ]]; then
    set -- account-auth recovery-password data-sync entity-lifecycle
fi
for suite in "$@"; do
    case "$suite" in
        account-auth|recovery-password|data-sync|entity-lifecycle) ;;
        *) echo "Unknown Auth online suite: $suite" >&2; exit 2 ;;
    esac
done
artifacts_dir=${MAESTRO_ARTIFACTS_DIR:-artifacts/maestro}
mkdir -p "$artifacts_dir"
artifacts_dir=$(mktemp -d "$artifacts_dir/online-XXXXXX")
echo "Results: $artifacts_dir"
# Wrapped tag chips currently have incorrect accessibility bounds in Auth.
: "${FIXTURE_MUTATION_TAG:=CI}"
: "${FIXTURE_LIFECYCLE_ACCOUNT:=lifecycle.fixture@example.org}"
: "${FIXTURE_LIFECYCLE_EDITED_ACCOUNT:=automation.fixture@example.org}"
: "${FIXTURE_LIFECYCLE_TAG:=Flow}"
credentials=museum/fixtures/public-test-credentials.json
fixture_basic_user_id=$(jq --raw-output '.accounts.basic.userId' "$credentials")
fixture_totp_secret=$(jq --raw-output '.accounts.totp.totpSecret' "$credentials")

fixture_env=(
    -e FIXTURE_BASIC_EMAIL="$(jq -r '.accounts.basic.email' "$credentials")"
    -e FIXTURE_BASIC_PASSWORD="$(jq -r '.accounts.basic.password' "$credentials")"
    -e FIXTURE_TOTP_EMAIL="$(jq -r '.accounts.totp.email' "$credentials")"
    -e FIXTURE_TOTP_PASSWORD="$(jq -r '.accounts.totp.password' "$credentials")"
    -e FIXTURE_RECOVERY_EMAIL="$(jq -r '.accounts.recovery.email' "$credentials")"
    -e FIXTURE_RECOVERY_PASSWORD="$(jq -r '.accounts.recovery.password' "$credentials")"
    -e FIXTURE_RECOVERY_KEY="$(jq -r '.accounts.recovery.recoveryKey' "$credentials")"
    -e FIXTURE_RECOVERED_PASSWORD="$(jq -r '.accounts.recovery.recoveredPassword' "$credentials")"
)

record_runtime_health() {
    local status=$1
    trap - EXIT
    # Bash 3.2 can report status 0 after an unbound-variable error in a function.
    if [[ "$tests_completed" == false && $status -eq 0 ]]; then
        status=1
    fi
    if [[ $status -ne 0 ]]; then
        # Capture while the emulator still exists, before the action tears it down.
        {
            echo "phase=$phase"
            date -u '+%Y-%m-%dT%H:%M:%SZ'
            adb devices -l || true
            printf 'adb_state='
            adb get-state || true
            printf 'boot_completed='
            adb shell getprop sys.boot_completed || true
            printf 'app_pid='
            adb shell pidof "$APP_ID" || true
            adb shell dumpsys meminfo "$APP_ID" || true
            adb shell dumpsys connectivity || true
        } > "$runtime_dir/$phase-device.txt" 2>&1
        # The next independent suite restores the fixture and removes these containers.
        docker compose --project-name "$AUTH_FIXTURE_COMPOSE_PROJECT" --file museum/compose.yaml \
            logs --no-color > "$runtime_dir/$phase-backend.log" 2>&1 || true
    fi
    exit "$status"
}

run_maestro() {
    local flow=$1
    local result_name=${MAESTRO_RESULT_NAME:-${flow##*/}}
    result_name=${result_name%.yaml}
    shift
    wait_for_android_network
    scripts/run-maestro.sh "$results_dir/$result_name.xml" "$debug_dir/$result_name" \
        -e ONLINE_ENDPOINT="$ONLINE_ENDPOINT" "${fixture_env[@]}" \
        "$@" "maestro/auth/online/$flow"
}

wait_for_android_network() {
    # Android can finish booting before Cronet has a default network.
    for _ in {1..30}; do
        if timeout 5 adb shell dumpsys connectivity |
            grep -E '^Active default network: [0-9]+' > /dev/null; then
            return
        fi
        sleep 2
    done
    echo "Android has no active default network; online UI tests have not started" >&2
    return 1
}

prepare_fixture_app() {
    local app_data_dir app_owner current_user preferences_dir preferences_file

    adb shell pm clear "$APP_ID" >/dev/null
    if [[ ${AUTH_APP_PREPARATION:-ui} == "ui" ]]; then
        preparation_count=$((preparation_count + 1))
        MAESTRO_RESULT_NAME="prepare-endpoint-$preparation_count" run_maestro subflows/configure-online-test-endpoint-ui.yaml
        return
    fi

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
    app_owner=$(adb shell stat -c '%u:%g' "$app_data_dir" | tr -d '\r')
    if [[ ! "$app_owner" =~ ^[0-9]+:[0-9]+$ ]]; then
        echo "Unable to determine the Auth app-data owner: $app_owner" >&2
        return 1
    fi

    adb shell "mkdir -p '$preferences_dir'"
    adb shell \
        "printf '%s\\n' '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?>' '<map>' '    <string name=\"flutter.endpoint\">$ONLINE_ENDPOINT</string>' '    <boolean name=\"flutter.has_shown_coach_mark_v2\" value=\"true\" />' '    <boolean name=\"flutter.ls_hide_app_content\" value=\"false\" />' '</map>' > '$preferences_file'"
    adb shell chown -R "$app_owner" "$preferences_dir"
    adb shell chmod 771 "$preferences_dir"
    adb shell chmod 660 "$preferences_file"
    adb shell restorecon "$preferences_dir"
    adb shell restorecon "$preferences_file"
    if ! adb shell \
        "grep -q 'name=\"flutter.endpoint\">$ONLINE_ENDPOINT</string>' '$preferences_file' && grep -q 'name=\"flutter.has_shown_coach_mark_v2\" value=\"true\"' '$preferences_file' && grep -q 'name=\"flutter.ls_hide_app_content\" value=\"false\"' '$preferences_file'"; then
        echo "Unable to preseed the Auth test preferences" >&2
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

wait_for_database() {
    local query=$1 state
    for _ in {1..60}; do
        state=$(query_fixture_db "$query")
        if [[ "$state" == t ]]; then
            return
        fi
        sleep 1
    done
    echo "Timed out waiting for database condition: $query (last result: $state)" >&2
    return 1
}

wait_for_entity_count_and_quiet() {
    local user_id=$1
    local previous_marker=$2
    local expected_count=$3
    local count last_marker="" marker stable_polls=0 state

    for _ in {1..90}; do
        state=$(query_fixture_db \
            "SELECT COUNT(*), MAX(updated_at) FROM authenticator_entity WHERE user_id = $user_id;")
        IFS='|' read -r count marker <<< "$state"
        if [[ "$count" == "$expected_count" && "$marker" =~ ^[0-9]+$ && "$marker" -gt "$previous_marker" ]]; then
            if [[ "$marker" == "$last_marker" ]]; then
                stable_polls=$((stable_polls + 1))
            else
                stable_polls=0
            fi
            if [[ $stable_polls -ge 4 ]]; then
                return
            fi
        else
            stable_polls=0
        fi
        last_marker=$marker
        sleep 1
    done
    echo "Timed out waiting for $expected_count quiet Auth entities for fixture user $user_id; last state: $state" >&2
    return 1
}

run_account_auth() {
    local fixture_totp_code previous_max_user_id signup_email signup_password
    signup_email="auth-maestro-signup-fixture-$(openssl rand -hex 6)@example.org"
    signup_password="AuthCi-$(openssl rand -hex 10)!"
    local code_account=first-key.fixture@example.org
    if [[ ${GITHUB_ACTIONS:-} == true ]]; then
        echo "::add-mask::$signup_password"
    fi

    prepare_fixture_app
    run_maestro login/totp-start.yaml
    fixture_totp_code=$(
        TOTP_SECRET="$fixture_totp_secret" \
            TOTP_MIN_VALIDITY_SECONDS=20 \
            python3 scripts/current-totp.py
    )
    run_maestro login/totp-complete.yaml \
        -e FIXTURE_TOTP_CODE="$fixture_totp_code"
    prepare_fixture_app
    run_maestro login/unknown-account.yaml \
        -e MISSING_EMAIL=missing.fixture@example.org
    previous_max_user_id=$(query_fixture_db "SELECT MAX(user_id) FROM users;")
    prepare_fixture_app
    run_maestro login/signup.yaml \
        -e ONLINE_OTT="$ONLINE_OTT" \
        -e ONLINE_EMAIL="$signup_email" \
        -e ONLINE_PASSWORD="$signup_password" \
        -e ONLINE_CODE_ACCOUNT="$code_account"
    wait_for_database "SELECT (SELECT COUNT(*) = 1 FROM authenticator_key WHERE user_id > $previous_max_user_id) AND (SELECT COUNT(*) = 1 FROM authenticator_entity WHERE user_id > $previous_max_user_id);"
    prepare_fixture_app
    run_maestro login/password.yaml \
        -e ONLINE_EMAIL="$signup_email" \
        -e ONLINE_PASSWORD="$signup_password" \
        -e ONLINE_CODE_ACCOUNT="$code_account"
}

run_recovery() {
    prepare_fixture_app
    run_maestro recovery/reset-password.yaml \
        -e ONLINE_OTT="$ONLINE_OTT"

    prepare_fixture_app
    run_maestro recovery/old-password.yaml
    prepare_fixture_app
    run_maestro recovery/login.yaml
}

run_data_sync() {
    local mutation_marker

    prepare_fixture_app
    run_maestro sync/account-state.yaml

    mutation_marker=$(query_fixture_db \
        "SELECT MAX(updated_at) FROM authenticator_entity WHERE user_id = $fixture_basic_user_id;")
    run_maestro sync/bulk-edit.yaml \
        -e FIXTURE_MUTATION_TAG="$FIXTURE_MUTATION_TAG"
    wait_for_database "SELECT COUNT(*) >= 2 FROM authenticator_entity WHERE user_id = $fixture_basic_user_id AND updated_at > $mutation_marker;"

    prepare_fixture_app
    run_maestro sync/relogin.yaml \
        -e FIXTURE_MUTATION_TAG="$FIXTURE_MUTATION_TAG"
    run_maestro sync/logout.yaml
}

run_entity_lifecycle() {
    local lifecycle_marker restore_marker

    prepare_fixture_app
    lifecycle_marker=$(query_fixture_db \
        "SELECT MAX(updated_at) FROM authenticator_entity WHERE user_id = $fixture_basic_user_id;")
    adb shell mkdir -p /sdcard/Download
    adb push \
        maestro/fixtures/lifecycle-import.txt \
        /sdcard/Download/auth_lifecycle_import.txt
    run_maestro lifecycle/create.yaml
    wait_for_entity_count_and_quiet "$fixture_basic_user_id" "$lifecycle_marker" 4

    prepare_fixture_app
    lifecycle_marker=$(query_fixture_db \
        "SELECT MAX(updated_at) FROM authenticator_entity WHERE user_id = $fixture_basic_user_id;")
    run_maestro lifecycle/edit-and-trash.yaml \
        -e FIXTURE_LIFECYCLE_ACCOUNT="$FIXTURE_LIFECYCLE_ACCOUNT" \
        -e FIXTURE_LIFECYCLE_EDITED_ACCOUNT="$FIXTURE_LIFECYCLE_EDITED_ACCOUNT" \
        -e FIXTURE_LIFECYCLE_TAG="$FIXTURE_LIFECYCLE_TAG"
    wait_for_entity_count_and_quiet "$fixture_basic_user_id" "$lifecycle_marker" 4

    prepare_fixture_app
    run_maestro subflows/login-basic.yaml

    restore_marker=$(query_fixture_db \
        "SELECT MAX(updated_at) FROM authenticator_entity WHERE user_id = $fixture_basic_user_id;")
    run_maestro lifecycle/restore.yaml \
        -e FIXTURE_LIFECYCLE_EDITED_ACCOUNT="$FIXTURE_LIFECYCLE_EDITED_ACCOUNT" \
        -e FIXTURE_LIFECYCLE_TAG="$FIXTURE_LIFECYCLE_TAG"
    wait_for_entity_count_and_quiet "$fixture_basic_user_id" "$restore_marker" 4

    run_maestro lifecycle/delete.yaml \
        -e FIXTURE_LIFECYCLE_EDITED_ACCOUNT="$FIXTURE_LIFECYCLE_EDITED_ACCOUNT"
    wait_for_database "SELECT COUNT(*) = 1 FROM authenticator_entity WHERE user_id = $fixture_basic_user_id AND is_deleted;"
}

run_suite() (
    set -e
    phase=$1
    debug_dir="$artifacts_dir/debug/$phase"
    results_dir="$artifacts_dir/results/$phase"
    runtime_dir="$artifacts_dir/runtime-health"
    preparation_count=0
    tests_completed=false

    mkdir -p "$debug_dir" "$results_dir" "$runtime_dir"
    trap 'record_runtime_health "$?"' EXIT
    ALLOW_AUTH_FIXTURE_RESTORE=1 museum/restore-fixture.sh
    case "$phase" in
        account-auth) run_account_auth ;;
        recovery-password) run_recovery ;;
        data-sync) run_data_sync ;;
        entity-lifecycle) run_entity_lifecycle ;;
    esac
    tests_completed=true
)

adb shell settings put system screen_off_timeout 2147483647
adb install -r "$AUTH_APK_PATH"
trap 'docker compose --project-name "$AUTH_FIXTURE_COMPOSE_PROJECT" --file museum/compose.yaml down --volumes --remove-orphans' EXIT

status=0
for suite in "$@"; do
    # Do not call run_suite in an if/||: that disables errexit inside its functions.
    set +e
    run_suite "$suite"
    suite_status=$?
    set -e
    echo "$suite: exit $suite_status"
    if [[ $suite_status -ne 0 ]]; then
        status=$suite_status
    fi
done
exit "$status"
