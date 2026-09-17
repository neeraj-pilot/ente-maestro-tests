#!/usr/bin/env bash

set -euo pipefail

serial=${ANDROID_SERIAL:?Set ANDROID_SERIAL}

readonly backup_dir="/sdcard/Download/EnteAuthBackups"
readonly temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

pull_latest_backup() {
    local kind="$1"
    local device_path=""
    local attempt
    # Android's Storage Access Framework can finish the write after the app's
    # short-lived success snackbar disappears.
    for attempt in {1..45}; do
        device_path="$(adb -s "$serial" shell "ls -1t $backup_dir/ente-auth-$kind-backup-*.json 2>/dev/null | head -1" | tr -d '\r')"
        if [[ -n "$device_path" ]]; then
            break
        fi
        sleep 2
    done
    if [[ -z "$device_path" ]]; then
        echo "Missing $kind Auth backup in $backup_dir" >&2
        exit 1
    fi
    local local_path="$temporary_dir/$kind.json"
    adb -s "$serial" pull "$device_path" "$local_path" > /dev/null
    echo "$local_path"
}

validate_backup() {
    local backup_path="$1"
    jq -e '
        .version == 1 and
        (.encryptedData | type == "string" and length > 0) and
        (.encryptionNonce | type == "string" and length > 0) and
        (.kdfParams.salt | type == "string" and length > 0)
    ' "$backup_path" > /dev/null
    if grep -Fq "backup.bot@github.test" "$backup_path"; then
        echo "Backup contains the test account in plaintext: $backup_path" >&2
        exit 1
    fi
}

validate_backup "$(pull_latest_backup daily)"
validate_backup "$(pull_latest_backup manual)"

echo "Verified encrypted automatic and manual Auth backups in $backup_dir"
