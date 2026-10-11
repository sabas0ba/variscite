#!/usr/bin/env python3
"""Package an Image and DTB for the Tang stop-and-wait UART boot ROM."""
import argparse
from pathlib import Path
import struct
import zlib

MAGIC = b"VBL1"
IMAGE_BASE = 0x80000000
DTB_BASE = 0x87E00000


def packet(command: bytes, address: int, data: bytes) -> bytes:
    if command not in (b"W", b"B") or not 1 <= len(data) <= 256:
        raise ValueError("invalid packet")
    header = MAGIC + struct.pack("<III", command[0], address, len(data))
    return header + struct.pack("<I", zlib.crc32(header + data)) + data


def package(image: bytes, dtb: bytes) -> bytes:
    if not 1 <= len(image) <= 32 * 1024 * 1024:
        raise ValueError("Image must be 1 byte .. 32 MiB")
    if not 40 <= len(dtb) <= 65536 or dtb[:4] != b"\xd0\x0d\xfe\xed":
        raise ValueError("DTB must have FDT magic and be 40 bytes .. 64 KiB")
    records = []
    for base, data in ((IMAGE_BASE, image), (DTB_BASE, dtb)):
        for offset in range(0, len(data), 256):
            records.append(packet(b"W", base + offset, data[offset:offset + 256]))
    manifest = struct.pack("<IIII", len(image), len(dtb), zlib.crc32(image), zlib.crc32(dtb))
    records.append(packet(b"B", IMAGE_BASE, manifest))
    return b"".join(records)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("dtb", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = package(args.image.read_bytes(), args.dtb.read_bytes())
    args.output.write_bytes(result)
    print(f"Boot package: {len(result)} bytes -> {args.output}")


if __name__ == "__main__":
    main()
