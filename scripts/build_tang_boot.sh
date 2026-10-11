#!/usr/bin/env bash
# Build the freestanding UART boot ROM using the pinned development container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
cross="${CROSS_COMPILE:-riscv-none-elf-}"
mkdir -p sim
"${cross}gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -Os \
    -ffreestanding -fno-builtin -fno-stack-protector -msmall-data-limit=0 -mno-relax \
    -nostdlib -nostartfiles -Wall -Wextra -Werror \
    -Wl,-T,fpga/firmware/tang_boot.ld,--build-id=none \
    fpga/firmware/tang_boot_start.S fpga/firmware/tang_boot.c -o sim/tang_boot.elf
"${cross}objcopy" -O binary sim/tang_boot.elf sim/tang_boot.bin
python3 - <<'PY'
from pathlib import Path
data = Path('sim/tang_boot.bin').read_bytes()
assert len(data) <= 4096
Path('sim/tang_boot.hex').write_text(''.join(
    f'{int.from_bytes(data[i:i+4], "little"):08x}\n'
    for i in range(0, 4096, 4)
))
print(f'Tang boot ROM: {len(data)} / 4096 bytes')
PY
