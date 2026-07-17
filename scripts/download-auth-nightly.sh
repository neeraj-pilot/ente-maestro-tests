#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/download-auth-nightly.sh [--output-dir <path>]

Downloads the newest Auth beta APK from ente/nightly and verifies it against
the release asset's SHA-256 digest. Prints the verified APK path.
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

IFS=$'\t' read -r release_tag apk_name apk_sha256 < <("$(dirname "${BASH_SOURCE[0]}")/resolve-auth-nightly.sh")

mkdir -p "$output_dir"
gh release download "$release_tag" \
    --repo ente/nightly \
    --pattern "$apk_name" \
    --pattern SHA256SUMS \
    --dir "$output_dir" \
    --clobber

apk_path="$output_dir/$apk_name"
expected_sha256="${apk_sha256#sha256:}"
actual_sha256=$(shasum -a 256 "$apk_path" | awk '{print $1}')
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Downloaded Auth APK does not match the resolved release asset" >&2
    exit 1
fi

checksum=$(grep -E "^${expected_sha256}[[:space:]]+\\*?${apk_name}$" "$output_dir/SHA256SUMS")
if [[ -z "$checksum" ]]; then
    echo "SHA256SUMS does not contain the resolved Auth APK" >&2
    exit 1
fi

echo "Verified $release_tag ($expected_sha256)" >&2
printf '%s\n' "$apk_path"
