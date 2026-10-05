#!/usr/bin/env bash
# Optional reference-reading tool. Run in the pinned development container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tools_dir="$root/logs/pdf-tools"
wheel="$tools_dir/pypdf-6.19.0-py3-none-any.whl"
checksum=7e5d6e730e7dae87d560a2cee218b852f6498c8be61966f3cd02ead971e48d14
url=https://files.pythonhosted.org/packages/3c/2c/c43c03eaf630435f023f1dc61ec4a4a78951ad5530a62c71cc89bde307b7/pypdf-6.19.0-py3-none-any.whl
mkdir -p "$tools_dir"
if [[ ! -f "$wheel" ]]; then
    curl --fail --location --retry 2 "$url" -o "$wheel.download"
    echo "$checksum  $wheel.download" | sha256sum --check
    mv "$wheel.download" "$wheel"
fi
echo "$checksum  $wheel" | sha256sum --check
PYTHONPATH="$wheel" python3 scripts/extract-reference-pdf.py "$@"
