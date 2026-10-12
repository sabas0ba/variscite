#!/usr/bin/env python3
"""Drive the Linux simulator only after each UART command has completed."""

import os
import selectors
import subprocess
import sys
import time


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: linux_console_test.py simulator [arguments...]")
    # Each stage must produce its own marker followed by a shell prompt.
    # A fixed sleep can send input before /init is ready on a busy host.
    stages = [
        (b"userspace is alive", b"veryl$ ", b"mandel\n"),
        (b"Mandelbrot set (Q16.16", b"veryl$ ", b"donut\n"),
        (b"donut: 24 frames rendered", b"veryl$ ", b"poweroff\n"),
        (b"reboot: Power down", b"[tb] SYSCON poweroff", None),
    ]
    process = subprocess.Popen(
        sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, bufsize=0,
    )
    stage = 0
    marker_seen = False
    pending = b""
    deadline = time.monotonic() + 600
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError(f"Linux console stage {stage} timed out")
                if not selector.select(min(remaining, 1)):
                    continue
                data = os.read(process.stdout.fileno(), 4096)
                if not data:
                    break
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
                if stage == len(stages):
                    continue
                pending += data
                marker, completion, command = stages[stage]
                if not marker_seen:
                    position = pending.find(marker)
                    if position >= 0:
                        marker_seen = True
                        pending = pending[position + len(marker):]
                if marker_seen and completion in pending:
                    if command is not None:
                        process.stdin.write(command)
                        process.stdin.flush()
                    stage += 1
                    marker_seen = False
                    pending = b""
                    deadline = time.monotonic() + 600
                # Retain enough suffix to match markers split across reads.
                pending = pending[-4096:]
        status = process.wait(timeout=10)
        if status or stage != len(stages):
            raise RuntimeError(f"Linux console failed: exit={status}, stages={stage}/{len(stages)}")
        print("[linux-console] PASS: /init, mandel, donut 24 frames, poweroff")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        process.stdin.close()
        process.stdout.close()


if __name__ == "__main__":
    main()
