#!/usr/bin/env python3
"""Decode a 32-cycle DDR array timeline from a board UART capture."""

import argparse
import pathlib
import re


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=pathlib.Path)
    args = parser.parse_args()
    frames = re.findall(rb"@([0-9A-F]{256})\r?\n", args.capture.read_bytes())
    if len(frames) != 1:
        parser.error(f"expected one 32-word timeline frame, found {len(frames)}")

    print("cycle gate burst valid dq1 dq0 dq8")
    for cycle in range(32):
        word = int(frames[0][cycle * 8 : (cycle + 1) * 8], 16)
        status = word >> 24
        print(
            f"{cycle:2d}    {status >> 7}    {(status >> 5) & 3}"
            f"     {(status >> 3) & 3}    {(word >> 16) & 255:02X}"
            f"  {(word >> 8) & 255:02X}  {word & 255:02X}"
        )


if __name__ == "__main__":
    main()
