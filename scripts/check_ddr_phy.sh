#!/usr/bin/env bash
# Run only in the pinned Gowin container. Structural check; never program output.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/sim/fpga/ddr_phy"
gowin="${GOWIN_HOME:-/opt/gowin/IDE}"
mkdir -p "$out"
veryl build > "$out/veryl.log" 2>&1
cd "$out"
env QT_QPA_PLATFORM=offscreen \
    LD_LIBRARY_PATH="/opt/gowin-runtime/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$gowin/lib" \
    "$gowin/bin/gw_sh" "$root/scripts/check_ddr_phy.tcl" > gowin.log 2>&1 || {
    tail -60 gowin.log >&2
    exit 1
}
report=impl/pnr/ddr_phy.rpt.txt
grep -q '^Placement and routing completed$' gowin.log
test "$report" -nt veryl.log
if grep -Eq 'ERROR|TA1132|TA1052' gowin.log; then
    echo 'GOWIN reported an error or an uncreated/ignored clock.' >&2
    exit 1
fi
grep -Eq '^[[:space:]]*DLL[[:space:]]*\| 1/4' "$report"
grep -Eq '^[[:space:]]*DQS[[:space:]]*\| 2/9' "$report"
grep -Eq '^[[:space:]]*CLKDIV[[:space:]]*\| 1/8' "$report"
grep -Eq '^[[:space:]]*DHCEN[[:space:]]*\| 1/16' "$report"
grep -Eq '^[[:space:]]*rPLL[[:space:]]*\| 1/4' "$report"
grep -Eq '^[[:space:]]*--IDES8_MEM[[:space:]]*\| 16[[:space:]]*$' "$report"
grep -Eq '^[[:space:]]*--OSER8[[:space:]]*\| 24[[:space:]]*$' "$report"
grep -Eq '^[[:space:]]*--OSER8_MEM[[:space:]]*\| 20[[:space:]]*$' "$report"
timing=impl/pnr/ddr_phy_tr_content.html
grep -A2 '<td>ddr_fast</td>' "$timing" | grep '<td>2.525</td>' > /dev/null
grep -A2 '<td>ddr_ctrl</td>' "$timing" | grep '<td>10.101</td>' > /dev/null
grep -A1 'Numbers of Setup Violated Endpoints' "$timing" | grep '<td>0</td>' > /dev/null
grep -A1 'Numbers of Hold Violated Endpoints' "$timing" | grep '<td>0</td>' > /dev/null
grep -Eq '^ddr_dq\[0\][[:space:]]*\|.*G5/5.*SSTL15.*INTERNAL.*1.5' "$report"
grep -Eq '^ddr_dqs_p\[1\][[:space:]]*\|.*J5,K6/4.*SSTL15D.*1.5' "$report"
echo "PASS: full PHY placed and routed. Reports: $out/impl/pnr"
echo 'Structural check only: never program the generated output.'
