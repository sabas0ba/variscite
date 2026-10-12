#!/usr/bin/env bash
# Build the freestanding UART boot ROM using the pinned development container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
cross="${CROSS_COMPILE:-riscv-none-elf-}"
mkdir -p sim
with_lcd="${WITH_LCD:-0}"
case "$with_lcd" in
    0) output=tang_boot ;;
    1) output=tang_boot_lcd ;;
    *) echo 'WITH_LCD must be 0 or 1' >&2; exit 2 ;;
esac
"${cross}gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -Os \
    -ffreestanding -fno-builtin -fno-stack-protector -msmall-data-limit=0 -mno-relax \
    -nostdlib -nostartfiles -Wall -Wextra -Werror \
    -Wl,-T,fpga/firmware/tang_boot.ld,--build-id=none \
    -DWITH_LCD="$with_lcd" fpga/firmware/tang_boot_start.S fpga/firmware/tang_boot.c -o "sim/$output.elf"
"${cross}objcopy" -O binary "sim/$output.elf" "sim/$output.bin"
python3 - "$output" <<'PY'
from pathlib import Path
import sys
output = sys.argv[1]
data = Path(f'sim/{output}.bin').read_bytes()
assert len(data) <= 4096
Path(f'sim/{output}.hex').write_text(''.join(
    f'{int.from_bytes(data[i:i+4], "little"):08x}\n'
    for i in range(0, 4096, 4)
))
print(f'Tang boot ROM: {len(data)} / 4096 bytes')
PY
