#!/usr/bin/env bash
# Build the bare-metal FPGA demo and emit the $readmemh image the RTL loads.
#
# Outputs sim/fpga/firmware.{elf,bin,hex}. The hex path is baked into the board
# tops as FpgaSoc's RAM_INIT, so synthesis must run from the repository root.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cross="${CROSS_COMPILE:-riscv-none-elf-}"
out="$root/sim/fpga"
mkdir -p "$out"

"${cross}gcc" \
    -march=rv32ima_zicsr -mabi=ilp32 \
    -Os -ffreestanding -fno-builtin -fno-stack-protector \
    -nostdlib -nostartfiles -Wall -Wextra -Werror \
    -Wl,--no-warn-rwx-segments \
    -T "$root/fpga/firmware/firmware.ld" \
    "$root/fpga/firmware/start.S" "$root/fpga/firmware/main.c" \
    -o "$out/firmware.elf"

# Neither libc nor libgcc is linked, so an accidental 64-bit divide or memcpy
# would only show up here.
if "${cross}nm" -u "$out/firmware.elf" | grep -q .; then
    echo "error: firmware has undefined symbols" >&2
    "${cross}nm" -u "$out/firmware.elf" >&2
    exit 1
fi

"${cross}objcopy" -O binary "$out/firmware.elf" "$out/firmware.bin"

python3 - "$out/firmware.bin" "$out/firmware.hex" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
data += b"\x00" * (-len(data) % 4)
with open(dst, "w") as f:
    for i in range(0, len(data), 4):
        f.write("%08x\n" % int.from_bytes(data[i:i + 4], "little"))
print("firmware: %d bytes, %d words -> %s" % (len(data), len(data) // 4, dst))
PY
