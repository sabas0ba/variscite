#!/usr/bin/env bash
# Boot Linux on the Verilator model.
#
# usage: run_linux.sh [--batch] [extra plusargs...]
#   --batch  wait for the shell and verify mandel/donut/poweroff responses
#
# Artifacts from linux/build_linux.sh are expected under sim/linux/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/sim/linux"
sim="$root/sim/tb_core_fast"

batch=0
if [[ "${1:-}" == "--batch" ]]; then
    batch=1
    shift
fi

for f in "$sim" "$out/Image" "$out/rv32ima_veryl.dtb"; do
    if [[ ! -e "$f" ]]; then
        echo "error: missing $f (run 'make tb-fast' and 'make linux-build')" >&2
        exit 2
    fi
done

mkdir -p "$root/logs/linux"

# mtimediv scales guest time against core cycles. It must be large enough that
# one timer tick (HZ=100 at a 1 MHz timebase = 10000 mtime units) costs far
# more core cycles than the tick handler itself, otherwise the kernel livelocks
# in the timer interrupt and never makes forward progress.
args=(
    "+kernel=$out/Image"
    "+dtb=$out/rv32ima_veryl.dtb"
    "+ramsize_mb=64"
    "+mtimediv=64"
    "+timeout=8000000000"
    "+conlog=$root/logs/linux/console.log"
)

if [[ "$batch" -eq 1 ]]; then
    python3 "$root/scripts/linux_console_test.py" "$sim" "${args[@]}" "$@"
else
    "$sim" "${args[@]}" "$@"
fi
