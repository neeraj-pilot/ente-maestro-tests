#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/maestro/runtime-health
emulator_pid=$(pgrep -n -f '/emulator/qemu/.*/qemu-system')
sudo gdb --batch -nx \
    -ex 'set debuginfod enabled off' \
    -ex 'set print frame-arguments none' \
    -ex 'handle SIGUSR1 nostop noprint pass' \
    -ex "attach $emulator_pid" -ex continue \
    -ex 'info sharedlibrary' -ex 'thread apply all bt 12' -ex 'x/8i $pc' -ex detach \
    > "artifacts/maestro/runtime-health/$1-exit.txt" 2>&1 &
exec .github/scripts/run-auth-online-tests.sh "$1"
