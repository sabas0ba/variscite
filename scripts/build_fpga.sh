#!/usr/bin/env bash
# Build (and optionally program) an FPGA bitstream for one of the board ports.
#
#   scripts/build_fpga.sh tang            # -> sim/fpga/tang/soc.fs
#   scripts/build_fpga.sh tang --prog     # ... and load it over USB
#   scripts/build_fpga.sh arty            # -> sim/fpga/arty/soc.bit
#
# Everything runs from the repository root: the board tops name the firmware
# image as a relative path, because $readmemh resolves against the working
# directory of whichever tool reads the Verilog.
#
# Tang Primer 20K needs only oss-cad-suite (yosys with the slang plugin,
# nextpnr-himbaechel, gowin_pack, openFPGALoader), which
# scripts/setup_toolchain.sh already installs.
#
# Arty A7 additionally needs the Xilinx place and route tools, which are not in
# oss-cad-suite. Install openXC7 (nextpnr-xilinx, prjxray-db and a chipdb for
# the part) and point PRJXRAY_DB and NEXTPNR_XILINX_CHIPDB at them.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# oss-cad-suite's yosys is a wrapper that resolves its libraries relative to its
# own path, so unlike verilator it cannot be reached through a symlink in
# /usr/local/bin. Put the suite's own bin directory on PATH instead.
if ! command -v yosys >/dev/null; then
    for d in "${OSS_CAD_SUITE:-}/bin" /opt/oss-cad-suite/bin \
             "$HOME/toolchain/oss-cad-suite/bin"; do
        if [[ -x "$d/yosys" ]]; then
            PATH="$d:$PATH"
            export PATH
            break
        fi
    done
fi

board="${1:-}"
prog=0
[[ "${2:-}" == "--prog" ]] && prog=1

RTL=(
    target/rv_pkg.sv target/alu.sv target/core.sv target/clint.sv
    target/plic.sv target/soc.sv target/uart.sv target/ram.sv
    target/power_on_reset.sv target/fpga_soc.sv
)

need() {
    command -v "$1" >/dev/null || { echo "error: $1 not found in PATH${2:+ ($2)}" >&2; exit 2; }
}

# Two frontends, on purpose:
#
#   - the Veryl output needs the slang plugin, because Veryl emits
#     `input var logic` in function arguments and yosys's own parser rejects it;
#   - the hand-written board files go through yosys's parser, because slang
#     elaborates strictly and does not know vendor primitives such as rPLL.
#
# synth_gowin keeps abc9. -noabc9 is not an alternative: it maps the same
# design to 17208 cells instead of 11192, and the placer then cannot find a
# legal placement on a part this full.
synth() { # <slang-top> <slang-extra> <verilog-files> <synth-command> <logfile>
    local read_v=""
    [[ -n "$3" ]] && read_v="read_verilog -sv $3"
    yosys -m slang -p "
        read_slang --top $1 ${RTL[*]} $2
        $read_v
        $4
    " > "$5" 2>&1 || { tail -30 "$5" >&2; exit 1; }
}

veryl build
scripts/build_fw.sh

case "$board" in
tang)
    out="sim/fpga/tang"
    mkdir -p "$out"
    need yosys
    need nextpnr-himbaechel
    need gowin_pack

    echo "==> synthesis"
    synth rv32ima_TangSoc target/tang_primer_20k/tang_soc.sv \
        "fpga/tang_primer_20k/pll.sv fpga/tang_primer_20k/top.sv" \
        "synth_gowin -top TangPrimer20k -json $out/soc.json" \
        "$out/yosys.log"

    echo "==> place and route"
    nextpnr-himbaechel \
        --device GW2A-LV18PG256C8/I7 \
        --vopt family=GW2A-18C \
        --vopt cst=fpga/tang_primer_20k/tang_primer_20k.cst \
        --json "$out/soc.json" \
        --write "$out/soc_pnr.json" \
        --freq 15 > "$out/nextpnr.log" 2>&1 \
        || { tail -30 "$out/nextpnr.log" >&2; exit 1; }
    grep -E "Max frequency|Device utilisation" -A22 "$out/nextpnr.log" | head -30 || true

    echo "==> bitstream"
    gowin_pack -d GW2A-18C -o "$out/soc.fs" "$out/soc_pnr.json" > "$out/pack.log" 2>&1 \
        || { tail -20 "$out/pack.log" >&2; exit 1; }
    ls -l "$out/soc.fs"

    if [[ "$prog" -eq 1 ]]; then
        need openFPGALoader
        # SRAM load: the design is gone at power off. Add -f to write it to the
        # board's flash instead.
        openFPGALoader -b tangprimer20k "$out/soc.fs"
    fi
    ;;

arty)
    out="sim/fpga/arty"
    mkdir -p "$out"
    need yosys

    echo "==> synthesis"
    synth rv32ima_ArtyA7 target/arty_a7/top.sv "" \
        "synth_xilinx -family xc7 -top rv32ima_ArtyA7 -json $out/soc.json" \
        "$out/yosys.log"
    grep -A28 "Printing statistics" "$out/yosys.log" | tail -30 || true

    part="${ARTY_PART:-xc7a35tcsg324-1}"
    chipdb="${NEXTPNR_XILINX_CHIPDB:-}"
    db="${PRJXRAY_DB:-}"

    if ! command -v nextpnr-xilinx >/dev/null || [[ -z "$chipdb" || -z "$db" ]]; then
        cat >&2 <<MSG

Synthesis finished: $out/soc.json

Place and route needs the Xilinx open toolchain, which oss-cad-suite does not
carry. Install openXC7 (https://github.com/openXC7), then re-run with:

    export NEXTPNR_XILINX_CHIPDB=/path/to/xc7a35t.bin
    export PRJXRAY_DB=/path/to/prjxray-db
    scripts/build_fpga.sh arty

MSG
        exit 3
    fi

    echo "==> place and route"
    nextpnr-xilinx \
        --chipdb "$chipdb" \
        --xdc fpga/arty_a7/arty_a7.xdc \
        --json "$out/soc.json" \
        --write "$out/soc_pnr.json" \
        --fasm "$out/soc.fasm" > "$out/nextpnr.log" 2>&1 \
        || { tail -30 "$out/nextpnr.log" >&2; exit 1; }

    echo "==> bitstream"
    fasm2frames --part "$part" --db-root "$db/artix7" "$out/soc.fasm" > "$out/soc.frames"
    xc7frames2bit \
        --part_file "$db/artix7/$part/part.yaml" \
        --part_name "$part" \
        --frm_file "$out/soc.frames" \
        --output_file "$out/soc.bit"
    ls -l "$out/soc.bit"

    if [[ "$prog" -eq 1 ]]; then
        need openFPGALoader
        openFPGALoader -b arty "$out/soc.bit"
    fi
    ;;

*)
    echo "usage: $0 {tang|arty} [--prog]" >&2
    exit 2
    ;;
esac
