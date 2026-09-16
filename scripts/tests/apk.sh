#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
mkdir -p "$temp_dir/bin"
export PATH="$temp_dir/bin:$PATH"
export MOCK_CALLS="$temp_dir/calls"
export NIGHTLY_RELEASES="$temp_dir/nightly.json" STABLE_RELEASES="$temp_dir/stable.json"
digest=$(printf 'fixture APK' | shasum -a 256 | awk '{print $1}')

jq -n --arg digest "sha256:$digest" '
    def release(id; tag; created): {
        draft: false, tag_name: tag, published_at: "2026-07-01T00:00:00Z",
        assets: [{id: id, name: "ente-auth-fixture.apk", state: "uploaded", created_at: created, digest: $digest}]
    };
    [release(101; "auth-v4.4.25-beta"; "2026-07-30T08:00:00Z"),
     release(102; "auth-v4.4.25-rc"; "2026-07-31T08:00:00Z"),
     (release(103; "auth-v4.4.26-rc"; "2026-08-01T08:00:00Z") | .draft = true),
     release(104; "auth-v4.4.26"; "2026-08-02T08:00:00Z"),
     release(201; "locker-v1.0.8-beta"; "2026-08-02T09:00:00Z"),
     (release(202; "auth-v4.4.26-beta"; "2026-08-02T10:00:00Z") | .assets[0].state = "new"),
     (release(203; "auth-v4.4.26-beta"; "2026-08-02T11:00:00Z") | .assets[0].name = "ente-locker.apk")]
' > "$NIGHTLY_RELEASES"
jq '[.[] | select(.tag_name == "auth-v4.4.26")]' "$NIGHTLY_RELEASES" > "$STABLE_RELEASES"
cp "$NIGHTLY_RELEASES" "$temp_dir/releases.json"

cat > "$temp_dir/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$MOCK_CALLS"
case "$*" in
    'api repos/ente/nightly/releases?per_page=100 --paginate')
        [[ ${API_MODE:-} != fail ]] || exit 22
        cat "$NIGHTLY_RELEASES"
        ;;
    'api repos/ente/ente/releases?per_page=100 --paginate') cat "$STABLE_RELEASES" ;;
    'api -H Accept: application/octet-stream repos/ente/'*'/releases/assets/'*)
        case ${DOWNLOAD_MODE:-} in
            fail) exit 1 ;;
            retry) [[ $(wc -l < "$MOCK_CALLS") -gt 1 ]] || exit 1 ;;
        esac
        printf 'fixture APK'
        ;;
    *) exit 2 ;;
esac
SH
cat > "$temp_dir/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$temp_dir/bin/gh" "$temp_dir/bin/sleep"

metadata=$("$root/scripts/apk.sh" resolve)
[[ $(jq -r '[.channel, .release_tag, .apk_asset_id, .apk_name, .apk_created_at, .apk_sha256, .source_repository] | @tsv' <<< "$metadata") == $'rc\tauth-v4.4.25-rc\t102\tente-auth-fixture.apk\t2026-07-31T08:00:00Z\tsha256:'"$digest"$'\tente/nightly' ]]
[[ $(wc -l < "$MOCK_CALLS") -eq 1 ]]

# Pagination must compare assets across pages, not just the last response.
jq -c '.[0:1], .[1:]' "$temp_dir/releases.json" > "$NIGHTLY_RELEASES"
[[ $("$root/scripts/apk.sh" resolve) == "$metadata" ]]

printf '[]' > "$NIGHTLY_RELEASES"
[[ $("$root/scripts/apk.sh" resolve | jq -r '[.channel, .source_repository, .apk_asset_id] | @tsv') == $'stable\tente/ente\t104' ]]

expect_failure() {
    if "$@" > "$temp_dir/output" 2> "$temp_dir/error"; then
        echo "Expected failure: $*" >&2
        exit 1
    fi
}

: > "$MOCK_CALLS"
expect_failure env API_MODE=fail "$root/scripts/apk.sh" resolve
[[ $(wc -l < "$MOCK_CALLS") -eq 1 ]]
printf '[]' > "$STABLE_RELEASES"
expect_failure "$root/scripts/apk.sh" resolve
grep -Fq 'No compatible published Auth APK' "$temp_dir/error"
for change in '.assets[0].digest = null' '.assets[0].digest = "sha256:bad"' '.assets[0].created_at = null' '.assets[0].id = null'; do
    jq "[.[] | select(.tag_name == \"auth-v4.4.25-rc\") | $change]" "$temp_dir/releases.json" > "$NIGHTLY_RELEASES"
    expect_failure "$root/scripts/apk.sh" resolve
done

: > "$MOCK_CALLS"
"$root/scripts/apk.sh" download "$metadata" "$temp_dir/auth.apk"
grep -Fxq 'api -H Accept: application/octet-stream repos/ente/nightly/releases/assets/102' "$MOCK_CALLS"
[[ $(shasum -a 256 "$temp_dir/auth.apk" | awk '{print $1}') == "$digest" ]]
expect_failure "$root/scripts/apk.sh" download "$(jq '.apk_sha256 = "sha256:bad"' <<< "$metadata")" "$temp_dir/auth.apk"
grep -Fq 'does not match' "$temp_dir/error"

: > "$MOCK_CALLS"
DOWNLOAD_MODE=retry "$root/scripts/apk.sh" download "$metadata" "$temp_dir/auth.apk"
[[ $(wc -l < "$MOCK_CALLS") -eq 2 ]]
: > "$MOCK_CALLS"
expect_failure env DOWNLOAD_MODE=fail "$root/scripts/apk.sh" download "$metadata" "$temp_dir/auth.apk"
[[ $(wc -l < "$MOCK_CALLS") -eq 3 ]]

cp "$temp_dir/releases.json" "$NIGHTLY_RELEASES"
[[ $("$root/scripts/apk.sh" fetch "$temp_dir/fetched") == "$temp_dir/fetched/ente-auth-fixture.apk" ]]
expect_failure env DOWNLOAD_MODE=fail "$root/scripts/apk.sh" fetch "$temp_dir/fetched"
[[ ! -s "$temp_dir/output" ]]
expect_failure env API_MODE=fail "$root/scripts/apk.sh" fetch "$temp_dir/fetched"
[[ ! -s "$temp_dir/output" ]]

echo "APK resolution, provenance, download and failure tests passed"
