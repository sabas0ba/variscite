#!/usr/bin/env bash
# Fetch the GOWIN CLI's Ubuntu runtime in a disposable development container.
# Explicit network/dependency approval is required before running this script.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/logs/gowin-runtime"
snapshot=20260901T000000Z
mkdir -p "$out/partial"
apt-get update --snapshot "$snapshot"
apt-get --snapshot "$snapshot" --download-only --no-install-recommends -y \
    -o "Dir::Cache::archives=$out" install \
    libgl1 libnss3 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxtst6 \
    libfontconfig1 libx11-xcb1 libxkbcommon0 libdbus-1-3 libasound2t64 libglib2.0-0t64
cd "$out"
sha256sum -c "$root/container/gowin-runtime.sha256"
sha256sum ./*.deb > SHA256SUMS
for package in ./*.deb; do
    dpkg-deb --show --showformat='${Package}\t${Version}\t${Architecture}\n' "$package"
done > versions.tsv
cmp versions.tsv "$root/container/gowin-runtime.versions.tsv"
