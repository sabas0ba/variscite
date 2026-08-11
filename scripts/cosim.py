#!/usr/bin/env python3
"""Compare this core's retire trace against Spike's execution log.

Both logs use the same "core   N: 0xPC (0xINSN)" line format. The two differ in
one respect: Spike emits that line for an instruction that traps and follows it
with an "exception ..." line, while this core only reports instructions that
actually retire. The normaliser therefore drops any Spike instruction line that
is immediately followed by an exception or interrupt line.

Comparison starts at the first entry to the test image (0x80000000) so the
differing boot stubs of the two models are ignored.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

INSN_RE = re.compile(r"^core\s+\d+:\s+0x([0-9a-f]{8})\s+\(0x([0-9a-f]+)\)")
EVENT_RE = re.compile(r"^core\s+\d+:\s+(exception|interrupt)\b.*?epc\s+0x([0-9a-f]+)")
ENTRY_PC = 0x80000000


def normalise(lines, drop_trapping):
    """Return the retired (pc, insn) sequence.

    Spike logs an instruction line before the exception it raised, so that
    instruction has to be removed - but only when the exception belongs to it.
    An instruction access fault is reported against the *target* address, and
    the branch or jump that got there did retire, so the epc is compared
    against the pending instruction's pc before dropping it.
    """
    out = []
    pending = None
    for line in lines:
        m = INSN_RE.match(line)
        if m:
            if pending is not None:
                out.append(pending)
            pending = (int(m.group(1), 16), int(m.group(2), 16))
            continue
        if drop_trapping:
            e = EVENT_RE.match(line)
            if e and pending is not None and int(e.group(2), 16) == pending[0]:
                pending = None  # the instruction did not retire
    if pending is not None:
        out.append(pending)

    for i, (pc, _) in enumerate(out):
        if pc == ENTRY_PC:
            return out[i:]
    return out


def run_spike(elf, isa, priv, out_path, timeout):
    cmd = ["spike", f"--isa={isa}", f"--priv={priv}", "-l", str(elf)]
    with open(out_path, "w") as f:
        try:
            proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=f,
                                  timeout=timeout)
        except subprocess.TimeoutExpired:
            print(f"spike timed out after {timeout}s", file=sys.stderr)
            return 124
    return proc.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf", type=Path)
    ap.add_argument("dut_log", type=Path, help="retire trace from tb_core")
    ap.add_argument("--spike-log", type=Path, required=True)
    # Zicclsm makes Spike complete misaligned accesses in hardware, which is
    # what this core does; without it Spike traps and the traces diverge on
    # every misaligned load or store.
    ap.add_argument("--isa", default="rv32ima_zicsr_zicntr_zifencei_zicclsm")
    ap.add_argument("--priv", default="mu")
    ap.add_argument("--limit", type=int, default=0,
                    help="compare at most N instructions (0 = all)")
    ap.add_argument("--timeout", type=int, default=120,
                    help="seconds to allow the reference model to run")
    args = ap.parse_args()

    rc = run_spike(args.elf, args.isa, args.priv, args.spike_log, args.timeout)
    if rc != 0:
        print(f"spike exited with {rc}", file=sys.stderr)
        return 2

    ref = normalise(args.spike_log.read_text(errors="replace").splitlines(), True)
    dut = normalise(args.dut_log.read_text(errors="replace").splitlines(), False)

    if not ref or not dut:
        print(f"empty trace (spike={len(ref)}, dut={len(dut)})", file=sys.stderr)
        return 2

    n = min(len(ref), len(dut))
    if args.limit:
        n = min(n, args.limit)

    for i in range(n):
        if ref[i] != dut[i]:
            lo = max(0, i - 3)
            print(f"divergence at instruction {i}:", file=sys.stderr)
            for j in range(lo, min(n, i + 2)):
                mark = ">>" if j == i else "  "
                print(f"{mark} spike 0x{ref[j][0]:08x} (0x{ref[j][1]:08x})   "
                      f"dut 0x{dut[j][0]:08x} (0x{dut[j][1]:08x})", file=sys.stderr)
            return 1

    # The testbench stops the moment tohost is written, while Spike keeps
    # spinning in the harness' write_tohost loop until its HTIF poll notices.
    # A shorter DUT trace is therefore expected; a longer one is not.
    if len(dut) > len(ref):
        print(f"dut ran past the reference (spike={len(ref)}, dut={len(dut)})",
              file=sys.stderr)
        return 1

    print(f"match: {n} instructions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
