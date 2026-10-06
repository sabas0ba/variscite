#!/usr/bin/env bash
# Build the CPU-driven DDR diagnostic into a 4 KiB boot ROM image.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cross="${CROSS_COMPILE:-riscv-none-elf-}"
program="${CPU_PROGRAM:-full}"
case "$program" in
    full) source_name=ddr_cpu ;;
    access) source_name=ddr_cpu_access ;;
    *) echo 'CPU_PROGRAM must be full or access' >&2; exit 2 ;;
esac
words="${FULL_WORDS:-33554432}"
hold_cycles="${HOLD_CYCLES:-2700000}"
if [[ ! "$words" =~ ^[0-9]+$ || ! "$hold_cycles" =~ ^[0-9]+$ ]]; then
    echo 'FULL_WORDS and HOLD_CYCLES must be decimal integers' >&2
    exit 2
fi
if (( words < 2 || words > 33554432 || hold_cycles < 1 || hold_cycles > 2147483647 )); then
    echo 'DDR diagnostic size or hold duration is outside its supported range' >&2
    exit 2
fi
output_name="${OUTPUT_NAME:-$source_name}"
if [[ ! "$output_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo 'OUTPUT_NAME must be a simple artifact name' >&2
    exit 2
fi
out="$root/sim/$output_name"
mkdir -p "$root/sim"
"${cross}gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
    -DFULL_WORDS="$words" -DHOLD_CYCLES="$hold_cycles" \
    -Wl,-Ttext=0x1000,-e,_start,--build-id=none \
    "$root/fpga/firmware/$source_name.S" -o "$out.elf"
"${cross}objcopy" -O binary "$out.elf" "$out.bin"
python3 - "$out.bin" "$out.hex" <<'PY'
import pathlib
import sys
data = pathlib.Path(sys.argv[1]).read_bytes()
if len(data) > 4096:
    raise SystemExit("DDR diagnostic exceeds its 4 KiB boot ROM")
data = data.ljust(4096, b"\0")
pathlib.Path(sys.argv[2]).write_text("".join(
    f"{int.from_bytes(data[i:i+4], 'little'):08x}\n"
    for i in range(0, len(data), 4)))
PY
