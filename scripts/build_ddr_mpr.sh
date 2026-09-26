#!/usr/bin/env bash
# Build the DDR3 MPR read-pattern probe in the pinned Gowin container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ "${DDR_ARRAY_MULTI:-0}" == 1 ]]; then
    name=ddr_array_multi
    top=rv32ima_TangDdrArrayMultiProbe
elif [[ "${DDR_ARRAY_TRAINED:-0}" == 1 ]]; then
    name=ddr_array_trained
    top=rv32ima_TangDdrArrayTrainedProbe
elif [[ "${DDR_ARRAY_ASSEMBLED:-0}" == 1 ]]; then
    name=ddr_array_assembled
    top=rv32ima_TangDdrArrayAssembledProbe
elif [[ "${DDR_ARRAY_RAW_SCALED:-0}" == 1 ]]; then
    name=ddr_array_raw_scaled
    top=rv32ima_TangDdrArrayRawScaledProbe
elif [[ "${DDR_ARRAY_RAW_BURST:-0}" == 1 ]]; then
    name=ddr_array_raw_burst
    top=rv32ima_TangDdrArrayRawBurstProbe
elif [[ "${DDR_ARRAY_STARTUP_SCAN:-0}" == 1 ]]; then
    name=ddr_array_startup_scan
    top=rv32ima_TangDdrArrayStartupScanProbe
elif [[ "${DDR_ARRAY_ALIGNED_SCAN:-0}" == 1 ]]; then
    name=ddr_array_aligned_scan
    top=rv32ima_TangDdrArrayAlignedScanProbe
elif [[ "${DDR_ARRAY_QUARTER_SCAN:-0}" == 1 ]]; then
    name=ddr_array_quarter_scan
    top=rv32ima_TangDdrArrayQuarterScanProbe
elif [[ "${DDR_ARRAY_CONTINUOUS_SCAN:-0}" == 1 ]]; then
    name=ddr_array_continuous_scan
    top=rv32ima_TangDdrArrayContinuousScanProbe
elif [[ "${DDR_ARRAY_PHASE_SCAN:-0}" == 1 ]]; then
    name=ddr_array_phase_scan
    top=rv32ima_TangDdrArrayPhaseScanProbe
elif [[ "${DDR_ARRAY_ALIGN_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_align_timeline
    top=rv32ima_TangDdrArrayAlignTimelineProbe
elif [[ "${DDR_ARRAY_PHASE_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_phase_timeline
    top=rv32ima_TangDdrArrayPhaseTimelineProbe
elif [[ "${DDR_ARRAY_EXPECTED_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_expected_timeline
    top=rv32ima_TangDdrArrayExpectedTimelineProbe
elif [[ "${DDR_ARRAY_FULL_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_full_timeline
    top=rv32ima_TangDdrArrayFullTimelineProbe
elif [[ "${DDR_ARRAY_EARLY_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_early_timeline
    top=rv32ima_TangDdrArrayEarlyTimelineProbe
elif [[ "${DDR_ARRAY_SIMPLE_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_simple_timeline
    top=rv32ima_TangDdrArraySimpleTimelineProbe
elif [[ "${DDR_ARRAY_TIMELINE:-0}" == 1 ]]; then
    name=ddr_array_timeline
    top=rv32ima_TangDdrArrayTimelineProbe
elif [[ "${DDR_ARRAY_FLAGS:-0}" == 1 ]]; then
    name=ddr_array_flags
    top=rv32ima_TangDdrArrayFlagsProbe
elif [[ "${DDR_ARRAY_MATCH:-0}" == 1 ]]; then
    name=ddr_array_match
    top=rv32ima_TangDdrArrayMatchProbe
elif [[ "${DDR_ARRAY_TRACE:-0}" == 1 ]]; then
    name=ddr_array_trace
    top=rv32ima_TangDdrArrayTraceProbe
elif [[ "${DDR_ARRAY_SAME:-0}" == 1 ]]; then
    name=ddr_array_same
    top=rv32ima_TangDdrArraySameProbe
elif [[ "${DDR_ARRAY_SCAN:-0}" == 1 ]]; then
    name=ddr_array_scan
    top=rv32ima_TangDdrArrayScanProbe
elif [[ "${DDR_ARRAY:-0}" == 1 ]]; then
    name=ddr_array
    top=rv32ima_TangDdrArrayProbe
elif [[ "${DDR_MPR_ALIGN:-0}" == 1 ]]; then
    name=ddr_mpr_align
    top=rv32ima_TangDdrMprAlignProbe
elif [[ "${DDR_MPR_DELAY:-0}" == 1 ]]; then
    name=ddr_mpr_delay
    top=rv32ima_TangDdrMprDelayProbe
else
    name=ddr_mpr
    top=rv32ima_TangDdrMprProbe
fi
export DDR_MPR_NAME="$name" DDR_MPR_TOP="$top"
out="$root/sim/fpga/$name"
gowin="${GOWIN_HOME:-/opt/gowin/IDE}"
mkdir -p "$out"
veryl build > "$out/veryl.log" 2>&1
cat fpga/tang_primer_20k/ddr_phy_check.cst fpga/tang_primer_20k/ddr_probe_uart.cst > "$out/$name.cst"
cat fpga/tang_primer_20k/ddr_read_probe.sdc > "$out/$name.sdc"
if [[ "$name" == ddr_array_startup_scan || "$name" == ddr_array_raw_* || "$name" == ddr_array_assembled || "$name" == ddr_array_trained || "$name" == ddr_array_multi ]]; then
    cat fpga/tang_primer_20k/ddr_phy_startup.sdc >> "$out/$name.sdc"
fi
cd "$out"
env QT_QPA_PLATFORM=offscreen \
    LD_LIBRARY_PATH="/opt/gowin-runtime/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$gowin/lib" \
    "$gowin/bin/gw_sh" "$root/scripts/build_ddr_mpr.tcl" > gowin.log 2>&1 || {
    tail -60 gowin.log >&2
    exit 1
}
report="impl/pnr/$name.rpt.txt"
timing="impl/pnr/${name}_tr_content.html"
grep -q '^Placement and routing completed$' gowin.log
test "$report" -nt veryl.log
if grep -Eq 'ERROR|TA1132|TA1052|No objects|no objects|cannot find|Cannot find' gowin.log; then
    echo 'GOWIN reported an error or an uncreated/ignored clock.' >&2
    exit 1
fi
test -s "impl/pnr/$name.fs"
grep -Eq '^[[:space:]]*DLL[[:space:]]*\| 1/4' "$report"
grep -Eq '^[[:space:]]*DQS[[:space:]]*\| 2/9' "$report"
grep -Eq '^[[:space:]]*rPLL[[:space:]]*\| 1/4' "$report"
grep -Eq '^ddr_dq\[0\][[:space:]]*\|.*G5/5.*SSTL15.*INTERNAL.*1.5' "$report"
grep -Eq '^ddr_clk_p[[:space:]]*\|.*J1,J3/5.*SSTL15D.*1.5' "$report"
grep -Eq '^o_uart_tx[[:space:]]*\|.*M11/2.*LVCMOS33.*3.3' "$report"
grep -A2 '<td>ddr_fast</td>' "$timing" | grep '<td>2.525</td>' > /dev/null
grep -A2 '<td>ddr_ctrl</td>' "$timing" | grep '<td>10.101</td>' > /dev/null
grep -A1 'Numbers of Setup Violated Endpoints' "$timing" | grep '<td>0</td>' > /dev/null
grep -A1 'Numbers of Hold Violated Endpoints' "$timing" | grep '<td>0</td>' > /dev/null
echo "DDR MPR probe: $out/impl/pnr/$name.fs"
