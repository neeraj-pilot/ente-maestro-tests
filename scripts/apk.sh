#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 resolve <auth|locker> | fetch <auth|locker> [output-directory] | download <metadata-json> <output-path>" >&2
    exit 2
}

resolve() {
    local app=$1
    case "$app" in auth|locker) ;; *) usage ;; esac
    gh api 'repos/ente/nightly/releases?per_page=100' --paginate | jq -esc --arg app "$app" '
        [add[]
            | select(.draft == false and (.tag_name | test("^" + $app + "-v[0-9]+\\.[0-9]+\\.[0-9]+-(beta|rc)$")))
            | . as $release | .assets[]?
            | select(.state == "uploaded" and (.name | test("^ente-" + $app + "-[^/]+\\.apk$")))
            | {
                release_tag: $release.tag_name,
                apk_asset_id: .id,
                apk_name: .name,
                apk_created_at: .created_at,
                apk_sha256: .digest
            }
        ] | if length == 0 then error("No compatible " + $app + " nightly APK was found") else max_by(.apk_created_at) end
        | if (.apk_asset_id | type == "number") and
           (.apk_created_at | type == "string" and length > 0) and
           (.apk_sha256 | type == "string" and test("^sha256:[a-fA-F0-9]{64}$"))
        then . else error("APK is missing immutable provenance or a valid SHA-256 digest") end
    '
}

download() {
    local metadata=$1 output=$2 asset_id expected actual attempt
    asset_id=$(jq -er '.apk_asset_id' <<< "$metadata")
    expected=$(jq -er '.apk_sha256 | ltrimstr("sha256:")' <<< "$metadata")
    mkdir -p "$(dirname "$output")"
    for attempt in 1 2 3; do
        if gh api -H 'Accept: application/octet-stream' "repos/ente/nightly/releases/assets/$asset_id" > "$output"; then
            break
        fi
        [[ $attempt -lt 3 ]] || return 1
        sleep $((attempt * 2))
    done
    actual=$(shasum -a 256 "$output" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        echo "Downloaded APK does not match the resolved release asset" >&2
        return 1
    fi
}

case "${1:-}" in
    resolve)
        [[ $# -eq 2 ]] || usage
        resolve "$2"
        ;;
    download)
        [[ $# -eq 3 ]] || usage
        download "$2" "$3"
        ;;
    fetch)
        [[ $# -ge 2 && $# -le 3 ]] || usage
        metadata=$(resolve "$2")
        output="${3:-artifacts/$2}/$(jq -r '.apk_name' <<< "$metadata")"
        download "$metadata" "$output"
        jq -r '"Verified \(.release_tag) asset \(.apk_asset_id), created \(.apk_created_at)"' <<< "$metadata" >&2
        printf '%s\n' "$output"
        ;;
    *) usage ;;
esac
