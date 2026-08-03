#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/resolve-nightly-apk.sh --app <auth|locker> [options]

Resolves the newest compatible APK asset published in ente/nightly, falling
back to the stable ente/ente release when no prerelease exists. Release tags
can be reused, so assets are ordered by their creation time.

Options:
  --app <auth|locker>       App to resolve.
  --github-output <path>    Write named values to a GitHub Actions output file.
  --releases-file <path>    Read nightly releases JSON from a file instead of the API.
  --stable-releases-file <path>
                            Read stable releases JSON from a file instead of the API.
  -h, --help                Show this help.
EOF
}

app=""
github_output=""
releases_file=""
stable_releases_file=""

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
        --stable-releases-file)
            stable_releases_file="${2:?--stable-releases-file requires a path}"
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
        nightly_tag_pattern="^${app}-v[0-9]+\\.[0-9]+\\.[0-9]+-(beta|rc)$"
        stable_tag_pattern="^${app}-v[0-9]+\\.[0-9]+\\.[0-9]+$"
        asset_pattern="^ente-${app}-.*\\.apk$"
        ;;
    *)
        echo "--app must be auth or locker" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ -n "$releases_file" ]]; then
    nightly_releases=$(jq -c 'if type == "array" then . else error("expected a releases array") end' "$releases_file")
    if [[ -n "$stable_releases_file" ]]; then
        stable_releases=$(jq -c 'if type == "array" then . else error("expected a releases array") end' "$stable_releases_file")
    else
        stable_releases='[]'
    fi
else
    if [[ -n "$stable_releases_file" ]]; then
        echo "--stable-releases-file requires --releases-file" >&2
        exit 2
    fi
    nightly_releases=$(gh api "repos/ente/nightly/releases?per_page=100" --paginate | jq -sc 'add')
    stable_releases=""
fi

resolve_from_releases() {
    local releases=$1
    local source_repository=$2
    local tag_pattern=$3
    local channel=$4

    jq -c \
    --arg app "$app" \
    --arg asset_pattern "$asset_pattern" \
    --arg tag_pattern "$tag_pattern" \
    --arg channel "$channel" \
    --arg source_repository "$source_repository" \
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
          channel: (if $channel == "prerelease" then ($release.tag_name | capture("-(?<channel>beta|rc)$").channel) else $channel end),
          release_tag: $release.tag_name,
          apk_asset_id: .id,
          apk_name: .name,
          apk_created_at: .created_at,
          apk_sha256: .digest,
          source_repository: $source_repository
        }
    ]
    | if length == 0 then empty else max_by(.apk_created_at) end
    ' <<< "$releases"
}

resolved=$(resolve_from_releases "$nightly_releases" "ente/nightly" "$nightly_tag_pattern" prerelease)
if [[ -z "$resolved" ]]; then
    if [[ -z "$releases_file" ]]; then
        stable_releases=$(gh api "repos/ente/ente/releases?per_page=100" --paginate | jq -sc 'add')
    fi
    resolved=$(resolve_from_releases "$stable_releases" "ente/ente" "$stable_tag_pattern" stable)
fi

if [[ -z "$resolved" ]]; then
    echo "No compatible published $app APK was found" >&2
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
