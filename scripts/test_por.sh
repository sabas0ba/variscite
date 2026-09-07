#!/usr/bin/env bash
# Check configuration reset before and after Gowin technology mapping.
# Requires the same pinned OSS CAD Suite as the Tang bitstream build.
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
out=sim/por
mkdir -p "$out"

yosys -m slang -p "
    read_slang --top rv32ima_PowerOnReset target/power_on_reset.sv
    proc
    write_verilog $out/rtl.v
    synth_gowin -top rv32ima_PowerOnReset
    write_verilog $out/mapped.v
" > "$out/yosys.log" 2>&1

iverilog -g2012 -s tb_power_on_reset -o "$out/rtl.vvp" \
    "$out/rtl.v" tb/tb_power_on_reset.sv
vvp "$out/rtl.vvp" | tee "$out/rtl.log"
iverilog -g2012 -s tb_power_on_reset -o "$out/mapped.vvp" \
    "$suite/share/yosys/gowin/cells_sim.v" "$out/mapped.v" tb/tb_power_on_reset.sv
vvp "$out/mapped.vvp" | tee "$out/mapped.log"
