#!/usr/bin/env bash

set -euo pipefail

export MAESTRO_CLI_NO_ANALYTICS=1
export MAESTRO_API_URL=http://127.0.0.1:9

app_id="io.ente.auth.independent"
readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/run-auth-android-local.sh --apk <path> [options]

Run Auth Android Maestro suites sequentially on one selected local device.

Options:
  --apk <path>       Auth APK to install before the run (required).
  --maestro <path>   Maestro executable. Defaults to MAESTRO_BIN or maestro on PATH.
  --app-id <id>      Auth application id. Defaults to the published independent Android app.
  --serial <serial>  adb device serial. Defaults to ANDROID_SERIAL or the only attached device.
  --suite <names>    Space-separated suite names: smoke, basics, organization, tags,
                    trash, imports, backup. Defaults to required (all hosted offline suites).
  --skip-install     Reuse the installed Auth app instead of installing the APK.
  -h, --help         Show this help.
EOF
}

apk_path=""
maestro_bin="${MAESTRO_BIN:-maestro}"
serial="${ANDROID_SERIAL:-}"
suite="required"
install_apk=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk)
            apk_path="${2:?--apk requires a path}"
            shift 2
            ;;
        --maestro)
            maestro_bin="${2:?--maestro requires an executable path}"
            shift 2
            ;;
        --app-id)
            app_id="${2:?--app-id requires an application id}"
            shift 2
            ;;
        --serial)
            serial="${2:?--serial requires a device serial}"
            shift 2
            ;;
        --suite)
            suite="${2:?--suite requires a suite name}"
            shift 2
            ;;
        --skip-install)
            install_apk=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$apk_path" ]]; then
    echo "--apk is required" >&2
    usage >&2
    exit 2
fi

if [[ ! -f "$apk_path" ]]; then
    echo "APK not found: $apk_path" >&2
    exit 2
fi

if [[ "$suite" == required ]]; then
    selection=$(python3 "$workspace_root/scripts/suites.py" --suite offline)
    suite=$(jq -r '[.offline.include[].suite] | join(" ")' <<< "$selection")
fi
read -r -a suites <<< "$suite"
if [[ ${#suites[@]} -eq 0 ]]; then
    echo "Select at least one Auth suite" >&2
    exit 2
fi
for suite in "${suites[@]}"; do
    case "$suite" in
        smoke|basics|organization|tags|trash|imports|backup) ;;
        *) echo "Unknown suite: $suite" >&2; exit 2 ;;
    esac
done

if ! "$maestro_bin" --version > /dev/null; then
    echo "Maestro executable is not runnable: $maestro_bin" >&2
    exit 2
fi

if [[ -z "$serial" ]]; then
    devices=()
    while IFS= read -r device; do
        devices+=("$device")
    done < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    if [[ ${#devices[@]} -ne 1 ]]; then
        echo "Set --serial or ANDROID_SERIAL when zero or multiple adb devices are attached" >&2
        exit 2
    fi
    serial="${devices[0]}"
fi

if [[ "$(adb -s "$serial" get-state)" != "device" ]]; then
    echo "adb device is not ready: $serial" >&2
    exit 2
fi

cd "$workspace_root"
artifacts_dir=${MAESTRO_ARTIFACTS_DIR:-artifacts/maestro/local}
mkdir -p "$artifacts_dir"
run_dir=$(mktemp -d "$artifacts_dir/auth-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
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

if [[ "$install_apk" == true ]]; then
    adb -s "$serial" uninstall "$app_id" > /dev/null 2>&1 || true
    adb -s "$serial" install -r "$apk_path"
fi

adb -s "$serial" shell settings put system screen_off_timeout 2147483647
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf '### Offline suites\n\n| Suite | Result |\n| --- | --- |\n' >> "$GITHUB_STEP_SUMMARY"
fi
status=0
for suite in "${suites[@]}"; do
    case "$suite" in
        smoke)
            flows=(maestro/auth/smoke/onboarding.yaml maestro/auth/smoke/offline-mode.yaml)
            ;;
        basics|organization|tags|trash)
            selection=$(python3 "$workspace_root/scripts/suites.py" --suite "$suite")
            flows=()
            while IFS= read -r flow; do
                flows+=("$flow")
            done < <(jq -r '.offline.include[].flows[]' <<< "$selection")
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
    APP_ID="$app_id" MAESTRO_BIN="$maestro_bin" MAESTRO_DEVICE="$serial" \
        scripts/run-maestro.sh "$run_dir/$suite/results.xml" "$run_dir/$suite/debug" \
        "${flows[@]}" || suite_status=$?
    if [[ $suite_status -eq 0 && "$suite" == backup ]]; then
        scripts/verify-local-auth-backups.sh --serial "$serial" || suite_status=$?
    fi
    result=success
    if [[ $suite_status -ne 0 ]]; then
        result=failure
        status=$suite_status
    fi
    echo "$suite: $result"
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        printf '| %s | %s |\n' "$suite" "$result" >> "$GITHUB_STEP_SUMMARY"
    fi
done
exit "$status"
