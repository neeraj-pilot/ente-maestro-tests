#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly resolver="$workspace_root/scripts/resolve-nightly-apk.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cat > "$temp_dir/releases.json" <<'JSON'
[
  {
    "draft": false,
    "tag_name": "auth-v4.4.25-beta",
    "published_at": "2026-07-31T08:00:00Z",
    "assets": [
      {
        "id": 101,
        "name": "ente-auth-v4.4.25-beta.apk",
        "created_at": "2026-07-30T08:00:00Z",
        "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "state": "uploaded"
      }
    ]
  },
  {
    "draft": false,
    "tag_name": "auth-v4.4.25-rc",
    "published_at": "2026-07-29T08:00:00Z",
    "assets": [
      {
        "id": 102,
        "name": "ente-auth-v4.4.25.apk",
        "created_at": "2026-07-31T08:00:00Z",
        "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "state": "uploaded"
      }
    ]
  },
  {
    "draft": true,
    "tag_name": "auth-v4.4.26-rc",
    "published_at": "2026-08-01T08:00:00Z",
    "assets": [
      {
        "id": 103,
        "name": "ente-auth-v4.4.26.apk",
        "created_at": "2026-08-01T08:00:00Z",
        "digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "state": "uploaded"
      }
    ]
  },
  {
    "draft": false,
    "tag_name": "auth-v4.4.26",
    "published_at": "2026-08-02T08:00:00Z",
    "assets": [
      {
        "id": 104,
        "name": "ente-auth-v4.4.26.apk",
        "created_at": "2026-08-02T08:00:00Z",
        "digest": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        "state": "uploaded"
      }
    ]
  },
  {
    "draft": false,
    "tag_name": "locker-v1.0.8-beta",
    "published_at": "2026-07-16T08:00:00Z",
    "assets": [
      {
        "id": 201,
        "name": "ente-locker-v1.0.8-beta.apk",
        "created_at": "2026-07-31T09:00:00Z",
        "digest": "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "state": "uploaded"
      }
    ]
  }
]
JSON

cat > "$temp_dir/stable-releases.json" <<'JSON'
[
  {
    "draft": false,
    "tag_name": "auth-v4.4.26",
    "published_at": "2026-08-02T08:00:00Z",
    "assets": [
      {
        "id": 104,
        "name": "ente-auth-v4.4.26.apk",
        "created_at": "2026-08-02T08:00:00Z",
        "digest": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        "state": "uploaded"
      }
    ]
  }
]
JSON

expected_auth=$'auth\trc\tauth-v4.4.25-rc\t102\tente-auth-v4.4.25.apk\t2026-07-31T08:00:00Z\tsha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\tente/nightly'
actual_auth="$($resolver --app auth --releases-file "$temp_dir/releases.json")"
if [[ "$actual_auth" != "$expected_auth" ]]; then
    echo "Unexpected Auth resolution: $actual_auth" >&2
    exit 1
fi

actual_auth="$($resolver --app auth --releases-file "$temp_dir/releases.json" --stable-releases-file "$temp_dir/stable-releases.json")"
if [[ "$actual_auth" != "$expected_auth" ]]; then
    echo "Expected an available Auth prerelease to take precedence: $actual_auth" >&2
    exit 1
fi

expected_stable_auth=$'auth\tstable\tauth-v4.4.26\t104\tente-auth-v4.4.26.apk\t2026-08-02T08:00:00Z\tsha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\tente/ente'
echo '[]' > "$temp_dir/no-nightly.json"
actual_stable_auth="$($resolver --app auth --releases-file "$temp_dir/no-nightly.json" --stable-releases-file "$temp_dir/stable-releases.json")"
if [[ "$actual_stable_auth" != "$expected_stable_auth" ]]; then
    echo "Unexpected stable Auth fallback: $actual_stable_auth" >&2
    exit 1
fi

expected_locker=$'locker\tbeta\tlocker-v1.0.8-beta\t201\tente-locker-v1.0.8-beta.apk\t2026-07-31T09:00:00Z\tsha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\tente/nightly'
actual_locker="$($resolver --app locker --releases-file "$temp_dir/releases.json")"
if [[ "$actual_locker" != "$expected_locker" ]]; then
    echo "Unexpected Locker resolution: $actual_locker" >&2
    exit 1
fi

github_output="$temp_dir/github-output"
$resolver --app auth --releases-file "$temp_dir/releases.json" --github-output "$github_output"
grep -Fx 'channel=rc' "$github_output" > /dev/null
grep -Fx 'apk_asset_id=102' "$github_output" > /dev/null
grep -Fx 'apk_created_at=2026-07-31T08:00:00Z' "$github_output" > /dev/null

jq 'map(select(.tag_name == "auth-v4.4.25-rc") | .assets[0].digest = null)' \
    "$temp_dir/releases.json" > "$temp_dir/missing-digest.json"
if $resolver --app auth --releases-file "$temp_dir/missing-digest.json" > /dev/null 2> "$temp_dir/error"; then
    echo "Expected a missing asset digest to fail" >&2
    exit 1
fi
grep -F 'missing a valid SHA-256 asset digest' "$temp_dir/error" > /dev/null

echo '[]' > "$temp_dir/no-releases.json"
if $resolver --app auth --releases-file "$temp_dir/no-releases.json" > /dev/null 2> "$temp_dir/error"; then
    echo "Expected an empty release list to fail" >&2
    exit 1
fi
grep -F 'No compatible published auth APK' "$temp_dir/error" > /dev/null

echo "Nightly APK resolver tests passed"
