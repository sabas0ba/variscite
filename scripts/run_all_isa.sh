#!/usr/bin/env bash
# Run all target riscv-tests and write a summary. Exits nonzero on any FAIL.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/logs/isa"
summary="$root/logs/isa/summary.txt"
: > "$summary"

pass=0
fail=0
while read -r t; do
    if "$root/scripts/run_isa.sh" "$t"; then
        result="PASS"
        pass=$((pass + 1))
    else
        result="FAIL"
        fail=$((fail + 1))
    fi
    detail="$(head -1 "$root/logs/isa/$t.out" 2>/dev/null || true)"
    printf '%-28s %s  (%s)\n' "$t" "$result" "$detail" | tee -a "$summary"
done < <("$root/scripts/list_tests.sh")

echo "----" | tee -a "$summary"
echo "pass=$pass fail=$fail" | tee -a "$summary"
[[ "$fail" -eq 0 ]]
