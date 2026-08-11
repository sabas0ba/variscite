#!/usr/bin/env bash
# Run every riscv-tests case under both this core and Spike and compare the
# retired instruction streams. Exits nonzero if any test diverges.
#
# Directed tests that touch testbench-specific devices (CLINT/PLIC/UART at this
# platform's addresses) are excluded: Spike models a different platform.
#
# rv32mi-p-breakpoint is excluded as well. Spike implements the optional Sdtrig
# debug triggers; this core reports none (tselect reads back non-zero), so the
# test legitimately takes a different path on each model.
#
# coverage_boost and irq_test are excluded too: the first probes
# implementation-defined WARL masks and executes wfi (which Spike waits in
# forever with no interrupt source), the second drives this platform's CLINT
# and PLIC.
set -uo pipefail
EXCLUDE="rv32mi-p-breakpoint coverage_boost irq_test"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/logs/cosim"
summary="$root/logs/cosim/summary.txt"
: > "$summary"

tests=()
while read -r t; do tests+=("third_party/riscv-tests/isa/$t"); done < <("$root/scripts/list_tests.sh")
for t in umode_test pmp_test; do
    [[ -f "$root/sim/$t.elf" ]] && tests+=("sim/$t.elf")
done

pass=0
fail=0
for elf in "${tests[@]}"; do
    name="$(basename "$elf")"
    name="${name%.elf}"
    if [[ " $EXCLUDE " == *" $name "* ]]; then
        printf '%-28s SKIP (excluded: see script header)\n' "$name" | tee -a "$summary"
        continue
    fi
    dut_log="$root/logs/isa/$name.trace.log"
    if [[ ! -f "$dut_log" ]]; then
        printf '%-28s SKIP (no dut trace; run make run-isa / cov-test first)\n' "$name" | tee -a "$summary"
        continue
    fi
    if out=$("$root/scripts/cosim.py" "$root/$elf" "$dut_log" \
                --spike-log "$root/logs/cosim/$name.spike.log" 2>&1); then
        printf '%-28s PASS  (%s)\n' "$name" "$out" | tee -a "$summary"
        pass=$((pass + 1))
    else
        printf '%-28s FAIL\n%s\n' "$name" "$out" | tee -a "$summary"
        fail=$((fail + 1))
    fi
done

echo "----" | tee -a "$summary"
echo "pass=$pass fail=$fail" | tee -a "$summary"
[[ "$fail" -eq 0 ]]
