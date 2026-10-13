#!/usr/bin/env bash
set -euo pipefail
: "${source:?Nix source path is required}"
: "${fixture:?Nix test fixture is required}"
: "${boundsPatch:?Nix bounds patch is required}"
: "${out:?Nix output path is required}"

extract_method() {
  awk '/^int Gowin::spi_put\(const uint8_t/ { copy=1 }
       /^int Gowin::spi_wait/ { copy=0 }
       copy { print }' src/gowin.cpp >gw2a-spi.inc
}

mkdir src
cp "$source/src/gowin.cpp" src/gowin.cpp
chmod u+w src/gowin.cpp
cp "$fixture" test.cpp
extract_method
c++ -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer test.cpp -o before
if ASAN_OPTIONS=detect_leaks=0 ./before >before.log 2>&1; then
  echo 'The unpatched GW2A transfer unexpectedly passed' >&2
  exit 1
fi
grep -q 'AddressSanitizer:.*buffer-overflow' before.log
patch -p1 <"$boundsPatch"
extract_method
c++ -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer test.cpp -o after
ASAN_OPTIONS=detect_leaks=0 ./after >after.log 2>&1
cat after.log
mkdir -p "$out"
cp before.log after.log "$out/"
