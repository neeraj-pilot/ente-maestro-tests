#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/maestro/runtime-health
emulator_pid=$(pgrep -n -f '/emulator/qemu/.*/qemu-system')
sudo gdb --batch -nx \
    -ex 'set debuginfod enabled off' \
    -ex 'set print frame-arguments none' \
    -ex 'handle all nostop noprint pass' \
    -ex 'handle SIGSEGV SIGABRT SIGILL SIGBUS stop print pass' \
    -ex "attach $emulator_pid" -ex continue \
    -ex 'bt 30' -ex 'info registers' -ex 'info proc mappings' \
    -ex 'x/64gx $rsp' -ex 'thread apply all bt 8' -ex detach \
    > "artifacts/maestro/runtime-health/$1-native.txt" 2>&1 &
exec .github/scripts/run-auth-online-tests.sh "$1"
