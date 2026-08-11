#!/usr/bin/env bash
# Fetch and install the pinned toolchain this project is verified against.
#
# Run this inside a container or a throwaway VM: it writes to /opt and
# /usr/local/bin and builds Spike from source. Nothing is fetched without a
# recorded SHA256 (release archives) or commit id (git repositories).
#
#   PREFIX=/opt scripts/setup_toolchain.sh          # toolchain only
#   WITH_SOURCES=1 scripts/setup_toolchain.sh       # also clone riscv-tests and Linux
#
# Versions here must stay in step with the table in README.md.
set -euo pipefail

PREFIX="${PREFIX:-/opt}"
BINDIR="${BINDIR:-/usr/local/bin}"
SRCDIR="${SRCDIR:-$HOME/src}"
JOBS="${JOBS:-$(nproc)}"
WITH_SOURCES="${WITH_SOURCES:-0}"

VERYL_VER=v0.20.3
VERYL_SHA=8e4f36919dcb676afa037867dd80e98172e2d19487825423f1fdedd1e87e9ab7

OSSCAD_VER=2026-08-10
OSSCAD_FILE=oss-cad-suite-linux-x64-20260810.tgz
OSSCAD_SHA=4d1137c56eaa7f2fadce7dd7f79b614cc5f7862684bcbe79765bb9a1f9037db0

XPACK_VER=v15.2.0-1
XPACK_FILE=xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz
XPACK_SHA=aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758

FLEX_VER=v2.6.4
FLEX_SHA=e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995

DTC_COMMIT=5ec18c3 # v1.7.2, only used when the distribution has no dtc
SPIKE_COMMIT=16c0b60
RISCV_TESTS_COMMIT=447a5fcb8253627ddb5f6a226f64e43463afcdd5
LINUX_TAG=v6.12

dl="$PREFIX/dl"
mkdir -p "$dl" "$BINDIR" "$SRCDIR"

fetch() { # <url> <file> <sha256>
    local url="$1" file="$dl/$2" sha="$3"
    if [[ -f "$file" ]] && echo "$sha  $file" | sha256sum -c --status; then
        echo "have $2"
        return
    fi
    echo "fetching $2"
    curl -fsSL -o "$file" "$url"
    echo "$sha  $file" | sha256sum -c -
}

# --- Veryl ---------------------------------------------------------------
fetch "https://github.com/veryl-lang/veryl/releases/download/$VERYL_VER/veryl-x86_64-linux.zip" \
    veryl.zip "$VERYL_SHA"
mkdir -p "$PREFIX/veryl"
unzip -qo "$dl/veryl.zip" -d "$PREFIX/veryl"
for b in "$PREFIX"/veryl/*; do ln -sf "$b" "$BINDIR/"; done

# --- Verilator (from oss-cad-suite) --------------------------------------
fetch "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSSCAD_VER/$OSSCAD_FILE" \
    "$OSSCAD_FILE" "$OSSCAD_SHA"
[[ -d "$PREFIX/oss-cad-suite" ]] || tar xzf "$dl/$OSSCAD_FILE" -C "$PREFIX"
for t in verilator verilator_coverage verilator_bin verilator_bin_dbg; do
    [[ -e "$PREFIX/oss-cad-suite/bin/$t" ]] && ln -sf "$PREFIX/oss-cad-suite/bin/$t" "$BINDIR/"
done

# --- RISC-V bare-metal GCC ----------------------------------------------
fetch "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/$XPACK_VER/$XPACK_FILE" \
    "$XPACK_FILE" "$XPACK_SHA"
[[ -d "$PREFIX/xpack-riscv-none-elf-gcc-15.2.0-1" ]] || tar xzf "$dl/$XPACK_FILE" -C "$PREFIX"
ln -sf "$PREFIX"/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-* "$BINDIR/"

# --- flex (needed by the kernel build) -----------------------------------
if ! command -v flex >/dev/null; then
    fetch "https://github.com/westes/flex/releases/download/$FLEX_VER/flex-2.6.4.tar.gz" \
        flex.tar.gz "$FLEX_SHA"
    tar xzf "$dl/flex.tar.gz" -C "$dl"
    (cd "$dl/flex-2.6.4" && ./configure --prefix=/usr/local >/dev/null && \
        make -j"$JOBS" >/dev/null && make install >/dev/null)
fi

# --- dtc -----------------------------------------------------------------
# Spike's configure hard-requires dtc, and spike calls it at run time to build
# its internal DTB. Install it before the Spike build; the kernel tree's copy is
# no use here because it only exists once the kernel has been built.
if ! command -v dtc >/dev/null; then
    if command -v apt-get >/dev/null; then
        apt-get install -y --no-install-recommends device-tree-compiler
    fi
fi
if ! command -v dtc >/dev/null; then
    [[ -d "$SRCDIR/dtc" ]] || git clone https://github.com/dgibson/dtc "$SRCDIR/dtc"
    git -C "$SRCDIR/dtc" checkout --quiet "$DTC_COMMIT"
    make -C "$SRCDIR/dtc" -j"$JOBS" NO_PYTHON=1 NO_YAML=1 PREFIX=/usr/local install-bin
fi

# --- Spike (reference model for the cosimulation) ------------------------
if [[ ! -x "$SRCDIR/spike/build/spike" ]]; then
    [[ -d "$SRCDIR/spike" ]] || git clone https://github.com/riscv-software-src/riscv-isa-sim "$SRCDIR/spike"
    git -C "$SRCDIR/spike" checkout --quiet "$SPIKE_COMMIT"
    mkdir -p "$SRCDIR/spike/build"
    (cd "$SRCDIR/spike/build" && ../configure --prefix=/usr/local >/dev/null && make -j"$JOBS")
fi
ln -sf "$SRCDIR/spike/build/spike" "$BINDIR/"

# --- sources (opt-in) ----------------------------------------------------
if [[ "$WITH_SOURCES" == "1" ]]; then
    root="$(cd "$(dirname "$0")/.." && pwd)"
    if [[ ! -d "$root/third_party/riscv-tests" ]]; then
        git clone --recurse-submodules https://github.com/riscv-software-src/riscv-tests \
            "$root/third_party/riscv-tests"
    fi
    git -C "$root/third_party/riscv-tests" checkout --quiet "$RISCV_TESTS_COMMIT"
    git -C "$root/third_party/riscv-tests" submodule update --init --recursive

    if [[ ! -d "$SRCDIR/linux" ]]; then
        git clone --depth 1 --branch "$LINUX_TAG" https://github.com/torvalds/linux "$SRCDIR/linux"
    fi
fi

echo
echo "installed:"
for t in veryl verilator verilator_coverage riscv-none-elf-gcc spike flex dtc; do
    printf '  %-22s %s\n' "$t" "$(command -v "$t" || echo 'not found')"
done
