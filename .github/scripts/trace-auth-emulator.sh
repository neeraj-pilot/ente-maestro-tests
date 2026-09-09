#!/usr/bin/env bash
set -euo pipefail

runtime_dir=artifacts/maestro/runtime-health
mkdir -p "$runtime_dir"
emulator_pid=$(pgrep -n -f '/emulator/qemu/.*/qemu-system')
sudo python3 .github/scripts/trace-process-exit.py "$emulator_pid" \
    > "$runtime_dir/$1-exit.txt" 2>&1 &
exec .github/scripts/run-auth-online-tests.sh "$1"
