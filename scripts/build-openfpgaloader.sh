#!/usr/bin/env bash
# Run inside the pinned Nix container; export Windows comparison suites.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flake="path:$root/container/openfpgaloader"
output="${1:-$root/tools/openfpgaloader}"
mkdir -p "$output" "$root/logs/openfpgaloader"
pages=(256 128 128-bounds 128-bounds-1mhz 128-bounds-read128)
if (($# > 1)); then pages=("${@:2}"); fi

for page in "${pages[@]}"; do
  case "$page" in
    256 | 128 | 128-bounds | 128-bounds-1mhz | 128-bounds-read128) ;;
    *)
      echo "Unknown comparison variant: $page" >&2
      exit 1
      ;;
  esac
  result=$(nix build "$flake#page$page" --no-link --print-out-paths \
    --print-build-logs 2> >(tee "$root/logs/openfpgaloader/build-page$page.log" >&2))
  destination="$output/page$page"
  # Refuse stale mixtures of DLLs from earlier builds.
  if [[ -e "$destination" ]]; then
    echo "Output already exists: $destination" >&2
    exit 1
  fi
  mkdir -p "$destination"
  cp -rL "$result/bin" "$result/share" "$destination/"
  printf '%s\n' "$result" >"$destination/nix-store-path.txt"
  (
    cd "$destination"
    find bin share -type f -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
  )
done

if [[ -f "$output/page256/share/source/spiFlash.cpp" && -f "$output/page128/share/source/spiFlash.cpp" ]]; then
  diff -u "$output/page256/share/source/spiFlash.cpp" \
    "$output/page128/share/source/spiFlash.cpp" >"$root/logs/openfpgaloader/page-size.diff" || {
    status=$?
    [[ $status -eq 1 ]] || exit "$status"
  }
fi
