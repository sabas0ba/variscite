#!/usr/bin/env bash
# Build the standalone 800x480 RGB LCD probe with the pinned FPGA toolchain.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
suite="${OSS_CAD_SUITE:-}"
if [[ -z "$suite" ]]; then
    for candidate in /opt/oss-cad-suite "$HOME/toolchain/oss-cad-suite"; do
        if [[ -x "$candidate/bin/yosys" ]]; then
            suite="$candidate"
            break
        fi
    done
fi
if [[ ! -x "$suite/bin/yosys" ]]; then
    echo 'Set OSS_CAD_SUITE to the pinned OSS CAD Suite directory' >&2
    exit 1
fi
export PATH="$suite/bin:$PATH"
out=sim/fpga/lcd
mkdir -p "$out"
veryl build > "$out/veryl.log" 2>&1
yosys -m slang -p "
    read_slang --top rv32ima_TangLcdTiming target/tang_primer_20k/lcd_timing.sv
    read_verilog fpga/tang_primer_20k/lcd_probe.sv
    synth_gowin -top TangLcdProbe -json $out/lcd.json
" > "$out/yosys.log" 2>&1
nextpnr-himbaechel --device GW2A-LV18PG256C8/I7 --vopt family=GW2A-18C \
    --vopt cst=fpga/tang_primer_20k/lcd_probe.cst \
    --json "$out/lcd.json" --write "$out/lcd-pnr.json" --freq 33 \
    > "$out/nextpnr.log" 2>&1
gowin_pack -d GW2A-18C -o "$out/lcd.fs" "$out/lcd-pnr.json" > "$out/pack.log" 2>&1
echo "LCD probe: $out/lcd.fs"
