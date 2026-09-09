#!/usr/bin/env bash
set -euo pipefail

runtime_dir=artifacts/maestro/runtime-health
mkdir -p "$runtime_dir"
emulator_pid=$(pgrep -n -f '/emulator/qemu/.*/qemu-system')
sudo strace -ff -tt -e trace=exit,exit_group -e signal=all \
    -p "$emulator_pid" -o "$runtime_dir/$1-qemu" \
    > "$runtime_dir/$1-tracer.txt" 2>&1 &
exec .github/scripts/run-auth-online-tests.sh "$1"
