#!/usr/bin/env python3
"""Check real Linux framebuffer writes captured by the Verilator memory model."""
import argparse
from pathlib import Path
import struct
import zlib


def check_frame(data, selection, position_x):
    if len(data) != 800 * 480 * 2:
        raise ValueError("incomplete framebuffer capture")
    pixels = struct.unpack("<384000H", data)
    colors = (0xF800, 0x07E0, 0x001F)

    def area(left, top, width, height, color):
        for y in range(top, top + height):
            if any(p != color for p in pixels[y * 800 + left:y * 800 + left + width]):
                raise ValueError(f"unexpected color in region {left},{top},{width},{height}")

    area(0, 0, 800, 48, 0x2128)
    area(0, 460, 800, 20, 0x1083)
    for button, color in enumerate(colors):
        y = 88 + button * 112
        area(24, y, 128, 6, 0xFFFF if button == selection else 0x630C)
        area(30, y + 6, 116, 76, color)
    area(position_x, 220, 48, 48, colors[selection])
    area(position_x - 3, 217, 54, 3, 0xFFFF)
    area(180, 76, 580, 8, 0x3186)
    if position_x != 360:
        area(357, 217, position_x - 360, 54, 0x3186)
    return pixels


def save_png(path, pixels):
    # Standalone preview of simulated framebuffer contents; no image package.
    scanlines = bytearray()
    for y in range(480):
        scanlines.append(0)
        for value in pixels[y * 800:(y + 1) * 800]:
            scanlines.extend(((value >> 11) * 255 // 31,
                              ((value >> 5) & 63) * 255 // 63,
                              (value & 31) * 255 // 31))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    path.write_bytes(b"\x89PNG\r\n\x1a\n" +
                     chunk(b"IHDR", struct.pack(">IIBBBBB", 800, 480, 8, 2, 0, 0, 0)) +
                     chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prefix", type=Path)
    args = parser.parse_args()
    for index, (selection, position_x) in enumerate(((0, 360), (1, 360), (1, 376))):
        path = Path(f"{args.prefix}-{index}.rgb565")
        pixels = check_frame(path.read_bytes(), selection, position_x)
        save_png(path.with_suffix(".png"), pixels)
    print("fbui capture PASS: RGB565 layout, buttons, color change, movement, erased old position")


if __name__ == "__main__":
    main()
