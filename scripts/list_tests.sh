#!/usr/bin/env bash
# List target riscv-tests (rv32{ui,um,ua,mi}-p-*) from the Makefrag files.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
isa="$root/third_party/riscv-tests/isa"

for suite in rv32ui rv32um rv32ua rv32mi; do
    awk -v suite="$suite" '
        $0 ~ "^" suite "_sc_tests" { collecting = 1; next }
        collecting && NF == 0     { collecting = 0 }
        collecting {
            for (i = 1; i <= NF; i++) {
                name = $i
                gsub(/\\/, "", name)
                if (name != "") print suite "-p-" name
            }
        }
    ' "$isa/$suite/Makefrag"
done
