#!/usr/bin/env bash

set -euo pipefail

config_file="$HOME/.android/avd/test.avd/config.ini"
test -f "$config_file"
sed -i '/^hw\.gpu\.enabled=/d; /^hw\.gpu\.mode=/d' "$config_file"
printf 'hw.gpu.enabled=no\nhw.gpu.mode=off\n' >> "$config_file"
