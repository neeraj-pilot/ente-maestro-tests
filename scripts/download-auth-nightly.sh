#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/download-auth-nightly.sh [--output-dir <path>]

Downloads the newest compatible published Auth APK and verifies it against the
release asset's SHA-256 digest. Prints the verified APK path.
EOF
}

output_dir="artifacts/auth"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            output_dir="${2:?--output-dir requires a path}"
            shift 2
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

IFS=$'\t' read -r app channel release_tag apk_asset_id apk_name apk_created_at apk_sha256 source_repository < <(
    "$(dirname "${BASH_SOURCE[0]}")/resolve-nightly-apk.sh" --app auth
)

mkdir -p "$output_dir"
apk_path="$output_dir/$apk_name"
gh api \
    -H 'Accept: application/octet-stream' \
    "repos/$source_repository/releases/assets/$apk_asset_id" > "$apk_path"

expected_sha256="${apk_sha256#sha256:}"
actual_sha256=$(shasum -a 256 "$apk_path" | awk '{print $1}')
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Downloaded Auth APK does not match the resolved release asset" >&2
    exit 1
fi

echo "Verified $release_tag asset $apk_asset_id created $apk_created_at ($expected_sha256)" >&2
printf '%s\n' "$apk_path"
