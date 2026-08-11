#!/usr/bin/env bash
# Build the rv32 NOMMU Linux boot set: init (FDPIC PIE), kernel Image, DTB.
#
# Requirements:
#   - Linux source tree (v6.12) at $LINUX_SRC
#   - riscv-none-elf- bare-metal toolchain in PATH (kernel is freestanding)
#   - flex/bison on the host
#
# Outputs under <repo>/sim/linux/: init, Image, rv32ima_veryl.dtb
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
LINUX_SRC="${LINUX_SRC:-$HOME/src/linux}"
CROSS="${CROSS_COMPILE:-riscv-none-elf-}"
JOBS="${JOBS:-$(nproc)}"
out="$root/sim/linux"
mkdir -p "$out"

# --- 1. userspace (must exist before the kernel builds the initramfs) ----
# Bare-metal ld has no -pie: link at a non-zero base without relaxation (which
# keeps every reference pc-relative), then patch e_type to ET_DYN so the FDPIC
# loader relocates each image as one block. A zero entry point would be
# skipped by that loader, hence the non-zero base in linux/init.ld.
# -fPIE keeps every symbol reference pc-relative (auipc based) so the image
# works at whatever base the FDPIC loader picks; -mno-relax and -msmall-data-
# limit=0 stop the assembler from rewriting those into gp-relative accesses,
# which would need a global pointer this freestanding userland never sets up.
CFLAGS_USER=(
    -march=rv32ima_zicsr -mabi=ilp32
    -Os -ffreestanding -fno-builtin -fno-stack-protector
    -fPIE -mno-relax -msmall-data-limit=0 -Wall -Wextra
    -I"$root/linux/user"
)

build_user() { # <name> <source...>
    local name="$1"
    shift
    local objs=()
    for src in "$@"; do
        local obj="$out/$name.$(basename "$src").o"
        "${CROSS}gcc" "${CFLAGS_USER[@]}" -c "$src" -o "$obj"
        objs+=("$obj")
    done
    "${CROSS}ld" -T "$root/linux/init.ld" --no-relax -o "$out/$name" "${objs[@]}"
    printf '\x03' | dd of="$out/$name" bs=1 seek=16 conv=notrunc status=none
    if "${CROSS}readelf" -r "$out/$name" | grep -q 'R_RISCV'; then
        echo "error: $name contains relocations" >&2
        exit 1
    fi
    if "${CROSS}nm" -u "$out/$name" | grep -q .; then
        echo "error: $name has undefined symbols (libgcc/libc are not linked)" >&2
        "${CROSS}nm" -u "$out/$name" >&2
        exit 1
    fi
}

build_user init "$root/linux/user/init.c" "$root/linux/user/spawn.S"
build_user donut "$root/linux/user/donut.c"
build_user mandelbrot "$root/linux/user/mandelbrot.c"

cat > "$out/initramfs.desc" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
dir /bin 0755 0 0
file /init $out/init 0755 0 0
file /bin/donut $out/donut 0755 0 0
file /bin/mandelbrot $out/mandelbrot 0755 0 0
EOF

# --- 2. kernel configuration --------------------------------------------
cd "$LINUX_SRC"
make ARCH=riscv CROSS_COMPILE="$CROSS" nommu_virt_defconfig
scripts/config --file .config \
    --enable  NONPORTABLE \
    --enable  ARCH_RV32I \
    --disable ARCH_RV64I \
    --disable RISCV_ISA_C \
    --disable RISCV_ISA_V \
    --disable RISCV_ISA_ZBA \
    --disable RISCV_ISA_ZBB \
    --disable RISCV_ISA_ZICBOM \
    --disable RISCV_ISA_ZICBOZ \
    --disable RISCV_ISA_ZAWRS \
    --disable RISCV_ISA_SVNAPOT \
    --disable RISCV_ISA_SVPBMT \
    --disable FPU \
    --enable  BINFMT_ELF_FDPIC \
    --enable  SERIAL_OF_PLATFORM \
    --enable  POWER_RESET \
    --enable  POWER_RESET_SYSCON \
    --enable  POWER_RESET_SYSCON_POWEROFF \
    --enable  MFD_SYSCON \
    --enable  BLK_DEV_INITRD \
    --set-str INITRAMFS_SOURCE "$out/initramfs.desc" \
    --set-str CMDLINE "earlycon console=ttyS0,1000000 panic=-1" \
    --enable  HZ_100 \
    --disable HZ_250 \
    --disable VIRTIO_MMIO \
    --disable VIRTIO_BLK \
    --disable VIRTIO_NET \
    --disable NET \
    --disable EXT2_FS \
    --disable MMC \
    --disable SERIAL_EARLYCON_SEMIHOST
make ARCH=riscv CROSS_COMPILE="$CROSS" olddefconfig

# sanity: must be rv32 nommu M-mode
grep -q '^CONFIG_ARCH_RV32I=y' .config
grep -q '^CONFIG_RISCV_M_MODE=y' .config
! grep -q '^CONFIG_MMU=y' .config
grep -q '^CONFIG_BINFMT_ELF_FDPIC=y' .config

# --- 3. build ------------------------------------------------------------
make ARCH=riscv CROSS_COMPILE="$CROSS" -j"$JOBS" Image
cp arch/riscv/boot/Image "$out/Image"

# --- 4. DTB (kernel-bundled dtc) ----------------------------------------
if [[ ! -x scripts/dtc/dtc ]]; then
    make ARCH=riscv CROSS_COMPILE="$CROSS" scripts
fi
scripts/dtc/dtc -I dts -O dtb -o "$out/rv32ima_veryl.dtb" \
    "$root/linux/rv32ima_veryl.dts"

echo "artifacts:"
ls -la "$out"
