#!/usr/bin/env bash
# Fail if coverage regressed against the documented budget.
#
# The budget is the set of points README.md justifies as structurally
# unreachable. Making it a gate rather than a report is the point: a change
# that leaves new code unexercised has to either cover it or argue for it in
# the README, not quietly lower the number.
#
# Run after `make coverage` (it reads logs/cov/summary.txt).
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
summary="$root/logs/cov/summary.txt"

# Uncovered points allowed per metric. See "カバレッジ基準と除外理由" in README.md.
MAX_LINE="${MAX_LINE:-4}"
MAX_BRANCH="${MAX_BRANCH:-2}"
MAX_EXPR="${MAX_EXPR:-13}"

if [[ ! -f "$summary" ]]; then
    echo "error: $summary not found (run 'make coverage' first)" >&2
    exit 2
fi

# Rows look like:  line      : 98.6% ( 280/ 284)
# The counts are space-padded inside the parentheses, so match rather than split.
metric() { # <name> -> "<covered> <total>"
    sed -n "s/^ *$1 *:.*(\( *[0-9]\+\)\/\( *[0-9]\+\)).*/\1 \2/p" "$summary"
}

rc=0
for m in line branch expr; do
    read -r covered total <<<"$(metric "$m")"
    if [[ -z "${total:-}" ]]; then
        echo "error: no '$m' row in $summary" >&2
        exit 2
    fi
    uncovered=$((total - covered))
    case "$m" in
        line)   budget="$MAX_LINE" ;;
        branch) budget="$MAX_BRANCH" ;;
        expr)   budget="$MAX_EXPR" ;;
    esac
    if [[ "$uncovered" -gt "$budget" ]]; then
        printf '%-7s FAIL  %d/%d uncovered, budget %d\n' "$m" "$uncovered" "$total" "$budget"
        rc=1
    else
        printf '%-7s ok    %d/%d uncovered, budget %d\n' "$m" "$uncovered" "$total" "$budget"
    fi
done

if [[ "$rc" -ne 0 ]]; then
    cat >&2 <<'MSG'

New uncovered points. Either exercise them from tests/*.S or a testbench in
src/tests.veryl, or - if they really are unreachable - record the reason in
README.md and raise the budget in this script in the same commit.
Uncovered points are marked '%000000' under logs/cov/annotated/.
MSG
fi
exit "$rc"
