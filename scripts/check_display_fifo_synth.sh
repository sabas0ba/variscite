#!/usr/bin/env bash
# Run in the pinned GOWIN container after Veryl build in the dev container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gowin="${GOWIN_HOME:-/opt/gowin/IDE}"
case "${1:-fifo}" in
    fifo) export DISPLAY_TOP=rv32ima_DdrDisplayFifo DISPLAY_OUTPUT=display_fifo ;;
    stream) export DISPLAY_TOP=rv32ima_DdrLcdStream DISPLAY_OUTPUT=display_stream ;;
    *) echo 'usage: check_display_fifo_synth.sh [fifo|stream]' >&2; exit 2 ;;
esac
out="$root/sim/fpga/$DISPLAY_OUTPUT"
mkdir -p "$out"
cd "$out"
touch synthesis.started
QT_QPA_PLATFORM=offscreen \
LD_LIBRARY_PATH="/opt/gowin-runtime/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$gowin/lib" \
    "$gowin/bin/gw_sh" "$root/scripts/check_display_fifo_synth.tcl" > gowin.log 2>&1
cat gowin.log
grep -q '^GowinSynthesis finish$' gowin.log
if grep -Eq '^ERROR|^FATAL' gowin.log; then exit 1; fi
test -s "impl/gwsynthesis/$DISPLAY_OUTPUT.vg"
# A flop/multiplexer implementation of the 4 KiB buffer is not acceptable.
report="impl/gwsynthesis/${DISPLAY_OUTPUT}_syn.rpt.html"
test "$report" -nt synthesis.started
grep -A1 '<b>BSRAM </b>' "$report" | grep -q '^<td>4</td>$'
