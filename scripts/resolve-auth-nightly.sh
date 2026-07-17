#!/usr/bin/env bash

set -euo pipefail

github_output=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --github-output)
            github_output="${2:?--github-output requires a path}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

release=$(gh api "repos/ente/nightly/releases?per_page=100" --jq '
  [.[] | select(
    .draft == false and
    (.tag_name | startswith("auth-v")) and
    (.tag_name | endswith("-beta"))
  )] | max_by(.published_at)
')
release_tag=$(jq -r '.tag_name' <<< "$release")
apk_name=$(jq -r '[.assets[] | select(.name | test("^ente-auth-.*\\.apk$"))] | if length == 1 then .[0].name else empty end' <<< "$release")
apk_sha256=$(jq -r '[.assets[] | select(.name | test("^ente-auth-.*\\.apk$"))] | if length == 1 then .[0].digest else empty end' <<< "$release")

if [[ -z "$release_tag" || "$release_tag" == "null" || -z "$apk_name" || -z "$apk_sha256" ]]; then
    echo "No Auth beta APK was found in the latest nightly release" >&2
    exit 1
fi

if [[ -n "$github_output" ]]; then
    {
        echo "release_tag=$release_tag"
        echo "apk_name=$apk_name"
        echo "apk_sha256=$apk_sha256"
    } >> "$github_output"
else
    printf '%s\t%s\t%s\n' "$release_tag" "$apk_name" "$apk_sha256"
fi
