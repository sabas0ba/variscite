#!/usr/bin/env python3
"""Extract reference PDF text with page numbers and the source digest."""

import argparse
import hashlib
from pathlib import Path

from pypdf import PdfReader


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--plain", action="store_true", help="Include rotated text using plain extraction")
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error("source and output must differ")
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    reader = PdfReader(args.source)
    with args.output.open("w", encoding="utf-8") as output:
        output.write(f"Source: {args.source}\nSHA256: {digest}\nPages: {len(reader.pages)}\n")
        for number, page in enumerate(reader.pages, start=1):
            output.write(f"\n=== PDF page {number} ===\n")
            output.write(page.extract_text(extraction_mode="plain" if args.plain else "layout"))
            output.write("\n")
    print(f"Extracted {len(reader.pages)} pages to {args.output}")


if __name__ == "__main__":
    main()
