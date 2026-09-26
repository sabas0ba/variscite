#!/usr/bin/env bash
# Check the clock primitive topology, without programming hardware.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/sim/fpga/ddr_clock"
gowin="${GOWIN_HOME:-/opt/gowin/IDE}"
mkdir -p "$out"
veryl build > "$out/veryl.log" 2>&1
cd "$out"
env QT_QPA_PLATFORM=offscreen \
    LD_LIBRARY_PATH="/opt/gowin-runtime/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$gowin/lib" \
    "$gowin/bin/gw_sh" "$root/scripts/check_ddr_clock.tcl" > gowin.log 2>&1 || {
    tail -40 gowin.log >&2
    exit 1
}
grep -q '^Placement and routing completed$' gowin.log
test impl/pnr/ddr_clock.rpt.txt -nt veryl.log
if grep -Eq 'ERROR|TA1132|TA1052' gowin.log; then
    echo 'GOWIN reported an error or an uncreated/ignored clock.' >&2
    exit 1
fi
timing=impl/pnr/ddr_clock_tr_content.html
grep -A2 '<td>ddr_fast</td>' "$timing" | grep -q '<td>2.525</td>'
grep -A2 '<td>ddr_ctrl</td>' "$timing" | grep -q '<td>10.101</td>'
echo "PASS: clock topology routed, generated periods 2.525 ns / 10.101 ns. Reports: $out/impl/pnr"
echo 'Structural check only: never program the generated output.'
