#!/usr/bin/env bash
# Build a Tang Primer 20K bring-up probe (fpga/tang_primer_20k/uart_probe.veryl).
#
#   scripts/build_probe.sh            # -> sim/fpga/probe/probe.fs    (sends 'U')
#   scripts/build_probe.sh loopback   # -> sim/fpga/probe/loopback.fs (a wire)
#   scripts/build_probe.sh clk        # -> sim/fpga/probe/clkprobe.fs (clock to tx)
#   scripts/build_probe.sh div        # -> sim/fpga/probe/divprobe.fs (clock / 2**24)
#
# Kept separate from scripts/build_fpga.sh because these are not ports of the
# SoC. They are the smallest designs that use the board's clock pin and its
# serial pins, so that a silent console can be blamed on one side or the other.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

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

case "${1:-tx}" in
tx)       name=probe;    top=rv32ima_TangUartProbe; cst=uart_probe.cst ;;
loopback) name=loopback; top=rv32ima_TangLoopback;  cst=loopback.cst   ;;
clk)      name=clkprobe; top=rv32ima_TangClockProbe; cst=clkprobe.cst  ;;
div)      name=divprobe; top=rv32ima_TangDivProbe;   cst=clkprobe.cst  ;;
*)        echo "usage: $0 [tx|loopback|clk|div]" >&2; exit 2 ;;
esac

out="sim/fpga/probe"
mkdir -p "$out"

veryl build

echo "==> synthesis"
yosys -m slang -p "
    read_slang --top $top target/tang_primer_20k/uart_probe.sv
    synth_gowin -top $top -json $out/$name.json
" > "$out/$name-yosys.log" 2>&1 || { tail -30 "$out/$name-yosys.log" >&2; exit 1; }

echo "==> place and route"
nextpnr-himbaechel \
    --device GW2A-LV18PG256C8/I7 \
    --vopt family=GW2A-18C \
    --vopt "cst=fpga/tang_primer_20k/$cst" \
    --json "$out/$name.json" \
    --write "$out/$name-pnr.json" \
    --freq 27 > "$out/$name-nextpnr.log" 2>&1 \
    || { tail -30 "$out/$name-nextpnr.log" >&2; exit 1; }

echo "==> bitstream"
gowin_pack -d GW2A-18C -o "$out/$name.fs" "$out/$name-pnr.json" \
    > "$out/$name-pack.log" 2>&1 || { tail -20 "$out/$name-pack.log" >&2; exit 1; }
ls -l "$out/$name.fs"
