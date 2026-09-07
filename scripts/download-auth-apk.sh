#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <source-repository> <asset-id> <sha256> <output-path>" >&2
    exit 2
fi

repository=$1
asset_id=$2
expected_sha256=${3#sha256:}
apk_path=$4
mkdir -p "$(dirname "$apk_path")"

for attempt in 1 2 3; do
    if gh api -H 'Accept: application/octet-stream' \
        "repos/$repository/releases/assets/$asset_id" > "$apk_path"; then
        break
    fi
    [[ $attempt -lt 3 ]] || exit 1
    sleep $((attempt * 2))
done

actual_sha256=$(shasum -a 256 "$apk_path" | awk '{print $1}')
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Downloaded Auth APK does not match the resolved release asset" >&2
    exit 1
fi
