#!/usr/bin/env bash
# Run a single riscv-tests ELF on the Verilator testbench.
# usage: run_isa.sh <test-name> [extra plusargs...]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$1"
shift || true

if [[ -f "$t" ]]; then
    elf="$t"
    t="$(basename "$t" .elf)"
else
    elf="$root/third_party/riscv-tests/isa/$t"
fi
mkdir -p "$root/logs/isa" "$root/logs/cov"
bin="$root/logs/isa/$t.bin"

riscv-none-elf-objcopy -O binary "$elf" "$bin"
tohost="$(riscv-none-elf-nm "$elf" | awk '$3 == "tohost" { print $1 }')"
if [[ -z "$tohost" ]]; then
    echo "error: tohost symbol not found in $elf" >&2
    exit 2
fi

"$root/sim/tb_core" \
    "+bin=$bin" \
    "+tohost=$tohost" \
    "+logfile=$root/logs/isa/$t.trace.log" \
    "+covfile=$root/logs/cov/$t.dat" \
    "$@" > "$root/logs/isa/$t.out" 2>&1
