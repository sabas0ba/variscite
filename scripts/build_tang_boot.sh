#!/usr/bin/env bash
# Build the freestanding UART boot ROM using the pinned development container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
cross="${CROSS_COMPILE:-riscv-none-elf-}"
mkdir -p sim
with_lcd="${WITH_LCD:-0}"
with_sd="${WITH_SD:-0}"
rom_bytes=4096
extra_sources=()
case "$with_lcd" in
    0) output=tang_boot ;;
    1) output=tang_boot_lcd ;;
    *) echo 'WITH_LCD must be 0 or 1' >&2; exit 2 ;;
esac
case "$with_sd" in
    0) ;;
    1) output=tang_boot_standalone; with_lcd=1; rom_bytes=8192
       extra_sources=(fpga/firmware/sd_spi.c fpga/firmware/sd_fat.c) ;;
    *) echo 'WITH_SD must be 0 or 1' >&2; exit 2 ;;
esac
"${cross}gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -Os \
    -ffreestanding -fno-builtin -fno-stack-protector -msmall-data-limit=0 -mno-relax \
    -nostdlib -nostartfiles -Wall -Wextra -Werror \
    -Wl,--defsym,ROM_BYTES="$rom_bytes",-T,fpga/firmware/tang_boot.ld,--build-id=none \
    -DWITH_LCD="$with_lcd" -DWITH_SD="$with_sd" \
    fpga/firmware/tang_boot_start.S fpga/firmware/tang_boot.c "${extra_sources[@]}" -o "sim/$output.elf"
"${cross}objcopy" -O binary "sim/$output.elf" "sim/$output.bin"
python3 - "$output" "$rom_bytes" <<'PY'
from pathlib import Path
import sys
output = sys.argv[1]
rom_bytes = int(sys.argv[2])
data = Path(f'sim/{output}.bin').read_bytes()
assert len(data) <= rom_bytes
Path(f'sim/{output}.hex').write_text(''.join(
    f'{int.from_bytes(data[i:i+4], "little"):08x}\n'
    for i in range(0, rom_bytes, 4)
))
print(f'Tang boot ROM: {len(data)} / {rom_bytes} bytes')
PY
