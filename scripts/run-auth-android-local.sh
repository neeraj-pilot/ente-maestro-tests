#!/usr/bin/env bash

set -euo pipefail

app_id="io.ente.auth.independent"
readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/run-auth-android-local.sh --apk <path> [options]

Run one Auth Android Maestro suite against an explicitly selected local device.

Options:
  --apk <path>       Auth APK to install before the run (required).
  --maestro <path>   Maestro executable. Defaults to MAESTRO_BIN or maestro on PATH.
  --app-id <id>      Auth application id. Defaults to the published independent Android app.
  --serial <serial>  adb device serial. Defaults to ANDROID_SERIAL or the only attached device.
  --suite <name>     smoke, setup, organization, settings, tags, trash, imports, backup, or required.
                    Defaults to required.
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

declare -a flows
case "$suite" in
    smoke)
        flows=(
            maestro/auth/smoke/onboarding.yaml
            maestro/auth/smoke/offline-mode.yaml
        )
        ;;
    setup)
        flows=(
            maestro/auth/offline/manual-setup.yaml
            maestro/auth/offline/manual-validation.yaml
        )
        ;;
    organization)
        flows=(
            maestro/auth/offline/code-lifecycle.yaml
            maestro/auth/offline/home-organization.yaml
            maestro/auth/offline/bulk-pin-edit.yaml
        )
        ;;
    settings)
        flows=(
            maestro/auth/offline/settings.yaml
            maestro/auth/offline/duplicate-codes.yaml
        )
        ;;
    tags)
        flows=(
            maestro/auth/offline/tags.yaml
            maestro/auth/offline/bulk-tag-edit.yaml
            maestro/auth/offline/bulk-tag-remove.yaml
        )
        ;;
    trash)
        flows=(
            maestro/auth/offline/trash-restore.yaml
            maestro/auth/offline/bulk-trash-restore.yaml
        )
        ;;
    imports)
        flows=(maestro/auth/offline/imports.yaml)
        ;;
    backup)
        flows=(maestro/auth/offline/local-backup.yaml)
        ;;
    required)
        flows=(
            maestro/auth/smoke/onboarding.yaml
            maestro/auth/smoke/offline-mode.yaml
            maestro/auth/offline/manual-setup.yaml
            maestro/auth/offline/manual-validation.yaml
            maestro/auth/offline/code-lifecycle.yaml
            maestro/auth/offline/home-organization.yaml
            maestro/auth/offline/bulk-pin-edit.yaml
            maestro/auth/offline/settings.yaml
            maestro/auth/offline/duplicate-codes.yaml
            maestro/auth/offline/tags.yaml
            maestro/auth/offline/bulk-tag-edit.yaml
            maestro/auth/offline/bulk-tag-remove.yaml
            maestro/auth/offline/trash-restore.yaml
            maestro/auth/offline/bulk-trash-restore.yaml
        )
        ;;
    *)
        echo "Unknown suite: $suite" >&2
        usage >&2
        exit 2
        ;;
esac

cd "$workspace_root"
mkdir -p artifacts/maestro/local

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

if [[ "$suite" == "imports" ]]; then
    wait_for_downloads
    adb -s "$serial" push maestro/fixtures/plain_text_import.txt /sdcard/Download/plain_text_import.txt
    adb -s "$serial" push maestro/fixtures/google_auth_migration.png /sdcard/Download/google_auth_migration.png
fi

if [[ "$suite" == "backup" ]]; then
    wait_for_downloads
    adb -s "$serial" shell "mkdir -p /sdcard/Download/EnteAuthBackups"
    adb -s "$serial" shell "rm -f /sdcard/Download/EnteAuthBackups/ente-auth-daily-backup-*.json /sdcard/Download/EnteAuthBackups/ente-auth-manual-backup-*.json"
fi

adb -s "$serial" shell settings put system screen_off_timeout 2147483647
"$maestro_bin" test \
    --no-ansi \
    --udid "$serial" \
    -e "APP_ID=$app_id" \
    --format JUNIT \
    --output "artifacts/maestro/local/${suite}-results.xml" \
    --debug-output "artifacts/maestro/local/${suite}-debug" \
    --flatten-debug-output \
    "${flows[@]}"

if [[ "$suite" == "backup" ]]; then
    scripts/verify-local-auth-backups.sh --serial "$serial"
fi
