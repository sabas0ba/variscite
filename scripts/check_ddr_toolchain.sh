#!/usr/bin/env bash
# Capability check only. Does not produce or program a bitstream.
# A failure means that this DQS-based PHY cannot use the selected toolchain.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
suite="${OSS_CAD_SUITE:-/opt/oss-cad-suite}"
export PATH="$suite/bin:$PATH"
out=sim/fpga/ddr_capability
mkdir -p "$out"
veryl build > "$out/veryl.log" 2>&1
yosys -V > "$out/versions.log"
nextpnr-himbaechel --version >> "$out/versions.log" 2>&1
yosys -p "
    read_verilog -sv target/tang_primer_20k/ddr_capability_probe.sv
    synth_gowin -top rv32ima_TangDdrCapabilityProbe -json $out/probe.json
" > "$out/yosys.log" 2>&1
nextpnr-himbaechel --device GW2A-LV18PG256C8/I7 --vopt family=GW2A-18C \
    --vopt cst=fpga/tang_primer_20k/tang_primer_20k.cst \
    --json "$out/probe.json" --no-route > "$out/nextpnr.log" 2>&1 || {
    tail -20 "$out/nextpnr.log" >&2
    exit 1
}
echo 'Placement passed; DDR PHY routing and hardware operation still need verification.'
