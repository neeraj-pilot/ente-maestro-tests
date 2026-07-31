#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/resolve-nightly-apk.sh --app <auth|locker> [options]

Resolves the newest compatible APK asset published in ente/nightly. Release
tags can be reused, so assets are ordered by their creation time.

Options:
  --app <auth|locker>       App to resolve.
  --github-output <path>    Write named values to a GitHub Actions output file.
  --releases-file <path>    Read GitHub releases JSON from a file instead of the API.
  -h, --help                Show this help.
EOF
}

app=""
github_output=""
releases_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            app="${2:?--app requires auth or locker}"
            shift 2
            ;;
        --github-output)
            github_output="${2:?--github-output requires a path}"
            shift 2
            ;;
        --releases-file)
            releases_file="${2:?--releases-file requires a path}"
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

case "$app" in
    auth|locker)
        tag_pattern="^${app}-v[0-9]+\\.[0-9]+\\.[0-9]+-(beta|rc)$"
        asset_pattern="^ente-${app}-.*\\.apk$"
        ;;
    *)
        echo "--app must be auth or locker" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ -n "$releases_file" ]]; then
    releases=$(jq -c 'if type == "array" then . else error("expected a releases array") end' "$releases_file")
else
    releases=$(gh api "repos/ente/nightly/releases?per_page=100" --paginate | jq -sc 'add')
fi

resolved=$(jq -c \
    --arg app "$app" \
    --arg asset_pattern "$asset_pattern" \
    --arg tag_pattern "$tag_pattern" \
    '
    [
      .[]
      | select(.draft == false)
      | select(.tag_name | test($tag_pattern))
      | . as $release
      | .assets[]?
      | select(.state == "uploaded")
      | select(.name | test($asset_pattern))
      | {
          app: $app,
          channel: ($release.tag_name | capture("-(?<channel>beta|rc)$").channel),
          release_tag: $release.tag_name,
          apk_asset_id: .id,
          apk_name: .name,
          apk_created_at: .created_at,
          apk_sha256: .digest,
          source_repository: "ente/nightly"
        }
    ]
    | if length == 0 then empty else max_by(.apk_created_at) end
    ' <<< "$releases")

if [[ -z "$resolved" ]]; then
    echo "No compatible published $app APK was found in ente/nightly" >&2
    exit 1
fi

channel=$(jq -r '.channel' <<< "$resolved")
release_tag=$(jq -r '.release_tag' <<< "$resolved")
apk_asset_id=$(jq -r '.apk_asset_id' <<< "$resolved")
apk_name=$(jq -r '.apk_name' <<< "$resolved")
apk_created_at=$(jq -r '.apk_created_at' <<< "$resolved")
apk_sha256=$(jq -r '.apk_sha256' <<< "$resolved")
source_repository=$(jq -r '.source_repository' <<< "$resolved")

if [[ ! "$apk_asset_id" =~ ^[0-9]+$ || -z "$apk_created_at" || "$apk_created_at" == "null" ]]; then
    echo "The resolved $app APK is missing immutable asset provenance" >&2
    exit 1
fi

if [[ ! "$apk_sha256" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
    echo "The resolved $app APK is missing a valid SHA-256 asset digest" >&2
    exit 1
fi

if [[ -n "$github_output" ]]; then
    {
        echo "app=$app"
        echo "channel=$channel"
        echo "release_tag=$release_tag"
        echo "apk_asset_id=$apk_asset_id"
        echo "apk_name=$apk_name"
        echo "apk_created_at=$apk_created_at"
        echo "apk_sha256=$apk_sha256"
        echo "source_repository=$source_repository"
    } >> "$github_output"
else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$app" \
        "$channel" \
        "$release_tag" \
        "$apk_asset_id" \
        "$apk_name" \
        "$apk_created_at" \
        "$apk_sha256" \
        "$source_repository"
fi
