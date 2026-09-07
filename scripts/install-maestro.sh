#!/usr/bin/env bash

set -euo pipefail

readonly version=2.10.0
readonly sha256=29b675e10cc12080e445e9bfb2e2b4e4dfb9c0f2e30d5884120d258b5e1cd991
archive="$RUNNER_TEMP/maestro.zip"

curl --fail --location --silent --show-error \
    --retry 3 --retry-all-errors --retry-delay 2 \
    "https://github.com/mobile-dev-inc/maestro/releases/download/cli-$version/maestro.zip" \
    --output "$archive"
echo "$sha256  $archive" | shasum -a 256 --check -
mkdir -p "$HOME/.maestro"
unzip -q -o "$archive" -d "$HOME/.maestro"
bin="$HOME/.maestro/maestro/bin"
installed_version=$("$bin/maestro" --version)
if [[ "$installed_version" != "$version" ]]; then
    echo "Expected Maestro $version, installed $installed_version" >&2
    exit 1
fi
echo "$bin" >> "$GITHUB_PATH"
echo "MAESTRO_VERSION=$version" >> "$GITHUB_ENV"
