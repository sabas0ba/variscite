#!/usr/bin/env bash
# Run in container/Gowin.Containerfile's environment. No hardware access.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
gowin="${GOWIN_HOME:-/opt/gowin/IDE}"
out="$root/sim/fpga/ddr_gowin"
mkdir -p "$out"
veryl build > "$out/veryl.log" 2>&1
cd "$out"
env QT_QPA_PLATFORM=offscreen \
    LD_LIBRARY_PATH="/opt/gowin-runtime/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$gowin/lib" "$gowin/bin/gw_sh" \
    "$root/scripts/check_ddr_gowin.tcl" > gowin.log 2>&1 || {
    tail -40 gowin.log >&2
    exit 1
}
report=impl/pnr/ddr_capability.rpt.txt
grep -q '^Placement and routing completed$' gowin.log
test "$report" -nt veryl.log
grep -Eq '^[[:space:]]*DLL[[:space:]]*\| 1/4' "$report"
grep -Eq '^[[:space:]]*DQS[[:space:]]*\| 1/9' "$report"
grep -Eq -- '--IDES4_MEM[[:space:]]*\| 1[[:space:]]*$' "$report"
grep -Eq -- '--OSER4_MEM[[:space:]]*\| 1[[:space:]]*$' "$report"
echo "PASS: DQS, DLL, IDES4_MEM and OSER4_MEM placed and routed. Reports: $out"
echo 'Structural probe only: never program the generated output.'
