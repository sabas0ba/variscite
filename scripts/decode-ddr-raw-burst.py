#!/usr/bin/env python3
"""Decode DdrArrayRawBurst UART frames; report full lane windows in beat order."""

import argparse
from pathlib import Path
import re


PATTERN = 0xA55A5AA5C33C3CC396696996F00F0FF0


def decode(payload: bytes) -> str:
    words = [int(payload[i:i + 8], 16) for i in range(0, 256, 8)]
    lines = []
    for column in range(2):
        base = column * 16
        expected = PATTERN ^ (((1 << 128) - 1) if column else 0)
        values = [sum(words[base + cycle * 4 + chunk] << (chunk * 32)
                      for chunk in range(4)) for cycle in range(3)]
        lines.append(f"column {column}: expected {expected:032X}")
        for cycle, value in enumerate(values):
            status = words[base + 12 + cycle]
            beats = " ".join(f"{(value >> (16 * beat)) & 0xffff:04X}" for beat in range(8))
            lines.append(f"  {('previous', 'valid', 'next')[cycle]:8s}: {value:032X} "
                         f"elapsed={status >> 5} gate={(status >> 4) & 1} "
                         f"burst={(status >> 2) & 3} valid={status & 3} beats=[{beats}]")
        for lane in range(2):
            stream = bytes((value >> (16 * beat + 8 * lane)) & 255
                           for value in values for beat in range(8))
            wanted = bytes((expected >> (16 * beat + 8 * lane)) & 255 for beat in range(8))
            offsets = [offset for offset in range(17) if stream[offset:offset + 8] == wanted]
            lines.append(f"  lane {lane}: {stream.hex(' ').upper()} expected={wanted.hex(' ').upper()} "
                         f"matching offsets={offsets}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    args = parser.parse_args()
    frames = re.findall(rb"@([0-9A-F]{256})\n", args.capture.read_bytes())
    if len(frames) != 1:
        parser.error(f"expected one complete frame, found {len(frames)}")
    print(decode(frames[0]))


if __name__ == "__main__":
    main()
