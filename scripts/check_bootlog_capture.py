#!/usr/bin/env python3
"""Decode the Linux 8x16 console font from a captured Tang RGB565 framebuffer."""
import argparse
from pathlib import Path
import re
import struct
import sys

sys.dont_write_bytecode = True
from check_fbui_capture import save_png


def read_font(path):
    source = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(), flags=re.S)
    data = bytes(int(value, 16) for value in re.findall(r"\b0x([0-9a-fA-F]{2})\s*,", source))
    if len(data) != 256 * 16:
        raise ValueError("expected the pinned Linux font_8x16.c with 4096 font bytes")
    return {data[code * 16:(code + 1) * 16]: chr(code) for code in range(32, 127)}


def decode_frame(data, font):
    if len(data) != 800 * 480 * 2:
        raise ValueError("incomplete boot console framebuffer capture")
    pixels = struct.unpack("<384000H", data)
    lines = []
    for row in range(30):
        line = []
        for column in range(100):
            glyph = bytearray()
            for y in range(row * 16, row * 16 + 16):
                bits = 0
                for x in range(column * 8, column * 8 + 8):
                    bits = (bits << 1) | int(pixels[y * 800 + x] != 0)
                glyph.append(bits)
            line.append(font.get(bytes(glyph), "?"))
        lines.append("".join(line).rstrip())
    text = "\n".join(lines) + "\n"
    # These must come from rendered glyphs, not the simulator's UART transcript.
    for marker in ("simplefb registered!", "Run /init as init process"):
        if marker not in text:
            raise ValueError(f"boot console pixels do not contain {marker!r}")
    return pixels, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("font", type=Path, help="pinned Linux lib/fonts/font_8x16.c")
    args = parser.parse_args()
    pixels, text = decode_frame(args.capture.read_bytes(), read_font(args.font))
    args.capture.with_suffix(".txt").write_text(text)
    save_png(args.capture.with_suffix(".png"), pixels)
    print("boot console capture PASS: rendered simplefb registration and /init boot messages")


if __name__ == "__main__":
    main()
