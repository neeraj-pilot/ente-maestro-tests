#!/usr/bin/env bash

set -euo pipefail

export MAESTRO_CLI_NO_ANALYTICS=1
# Analytics opt-out does not cover error reports (Maestro issue #3488).
export MAESTRO_API_URL=http://127.0.0.1:9

report=${1:?Expected JUnit report path}
debug_dir=${2:?Expected debug directory}
shift 2
mkdir -p "$(dirname "$report")" "$debug_dir"

if [[ -n ${MAESTRO_DEVICE:-} ]]; then
    set -- --device "$MAESTRO_DEVICE" "$@"
fi
"${MAESTRO_BIN:-maestro}" test --no-ansi \
    --format JUNIT --output "$report" \
    --debug-output "$debug_dir" --flatten-debug-output \
    -e APP_ID="${APP_ID:?}" "$@"

if [[ ! -s "$report" ]]; then
    echo "Maestro did not produce a nonempty JUnit report: $report" >&2
    exit 1
fi
# Maestro can exit successfully after the emulator crashes during driver cleanup.
if [[ -n ${MAESTRO_DEVICE:-} ]]; then
    adb -s "$MAESTRO_DEVICE" shell true
else
    adb shell true
fi
