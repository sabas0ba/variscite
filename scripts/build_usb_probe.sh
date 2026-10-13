#!/usr/bin/env bash
# Build a short DDR-resident USB diagnostic payload in the pinned container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
cross="${CROSS_COMPILE:-riscv-none-elf-}"
mkdir -p sim/usb-probe
export TMPDIR="$root/sim/usb-probe"
name=probe
extra=()
case "${USB_HID_PROBE:-0}" in
    0) ;;
    1) name=hid_probe; extra=(-DUSB_HID_PROBE=1 linux/user/usb_hid.c) ;;
    *) echo 'USB_HID_PROBE must be 0 or 1' >&2; exit 2 ;;
esac
"${cross}gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -Os \
    -ffreestanding -fno-builtin -fno-stack-protector -msmall-data-limit=0 -mno-relax \
    -nostdlib -nostartfiles -Wall -Wextra -Werror -Ilinux/user \
    -Wl,-T,fpga/firmware/ddr_payload.ld,--build-id=none \
    fpga/firmware/tang_boot_start.S fpga/firmware/usb_probe.c linux/user/usb_host.c \
    "${extra[@]}" -o "sim/usb-probe/$name.elf"
"${cross}objcopy" -O binary "sim/usb-probe/$name.elf" "sim/usb-probe/$name.bin"
dtc -I dts -O dtb -o "sim/usb-probe/$name.dtb" linux/tang_primer_20k_lcd.dts
python3 scripts/pack_tang_boot.py "sim/usb-probe/$name.bin" "sim/usb-probe/$name.dtb" "sim/usb-probe/$name.vbl"
"${cross}size" "sim/usb-probe/$name.elf"
