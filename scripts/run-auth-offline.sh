#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."
: "${AUTH_APK_PATH:?Set AUTH_APK_PATH to the Auth nightly APK}"
if [[ ! -f "$AUTH_APK_PATH" ]]; then
    echo "APK not found: $AUTH_APK_PATH" >&2
    exit 2
fi
export APP_ID=${APP_ID:-io.ente.auth.independent}
if [[ $# -eq 0 ]]; then
    suite_names=$(python3 scripts/suites.py --suite offline | jq -r '[.offline[].suite] | join(" ")')
    read -r -a suites <<< "$suite_names"
else
    suites=("$@")
fi
for suite in "${suites[@]}"; do
    case "$suite" in
        smoke|basics|organization|tags|trash|imports|backup) ;;
        *) echo "Unknown Auth offline suite: $suite" >&2; exit 2 ;;
    esac
done

serial=${ANDROID_SERIAL:-}
if [[ -z "$serial" ]]; then
    # adb reports an error when zero or multiple devices are attached.
    serial=$(adb get-serialno)
fi
export MAESTRO_DEVICE="$serial"
adb -s "$serial" get-state > /dev/null

artifacts_dir=${MAESTRO_ARTIFACTS_DIR:-artifacts/maestro}
mkdir -p "$artifacts_dir"
run_dir=$(mktemp -d "$artifacts_dir/offline-XXXXXX")
echo "Results: $run_dir"

wait_for_downloads() {
    local attempt
    for attempt in {1..30}; do
        if timeout 5 adb -s "$serial" shell '[ -d /sdcard/Download ]' > /dev/null 2>&1; then
            return
        fi
        sleep 2
    done
    echo "Android Downloads storage is not ready on $serial" >&2
    exit 1
}

adb -s "$serial" uninstall "$APP_ID" > /dev/null 2>&1 || true
adb -s "$serial" install -r "$AUTH_APK_PATH"

adb -s "$serial" shell settings put system screen_off_timeout 2147483647
status=0
for suite in "${suites[@]}"; do
    case "$suite" in
        smoke)
            flows=(maestro/auth/smoke/onboarding.yaml maestro/auth/smoke/offline-mode.yaml)
            ;;
        basics|organization|tags|trash)
            selection=$(python3 "scripts/suites.py" --suite "$suite")
            flows=()
            while IFS= read -r flow; do
                flows+=("$flow")
            done < <(jq -r '.offline[].flows[]' <<< "$selection")
            ;;
        imports)
            flows=(maestro/auth/offline/imports.yaml)
            wait_for_downloads
            adb -s "$serial" push maestro/fixtures/plain_text_import.txt /sdcard/Download/plain_text_import.txt
            adb -s "$serial" push maestro/fixtures/google_auth_migration.png /sdcard/Download/google_auth_migration.png
            ;;
        backup)
            flows=(maestro/auth/offline/local-backup.yaml)
            wait_for_downloads
            adb -s "$serial" shell "mkdir -p /sdcard/Download/EnteAuthBackups"
            adb -s "$serial" shell "rm -f /sdcard/Download/EnteAuthBackups/ente-auth-daily-backup-*.json /sdcard/Download/EnteAuthBackups/ente-auth-manual-backup-*.json"
            ;;
    esac

    suite_status=0
    scripts/run-maestro.sh "$run_dir/$suite/results.xml" "$run_dir/$suite/debug" \
        "${flows[@]}" || suite_status=$?
    if [[ $suite_status -eq 0 && "$suite" == backup ]]; then
        ANDROID_SERIAL="$serial" scripts/verify-local-auth-backups.sh || suite_status=$?
    fi
    result=success
    if [[ $suite_status -ne 0 ]]; then
        result=failure
        status=$suite_status
    fi
    echo "$suite: $result"
done
exit "$status"
