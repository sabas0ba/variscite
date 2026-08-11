SHELL := /bin/bash

RISCV_PREFIX ?= riscv-none-elf-
TESTS_DIR    := third_party/riscv-tests/isa
SIM          := sim/tb_core
TESTS        := $(shell scripts/list_tests.sh)

.PHONY: all lint veryl-build veryl-test tb tb-fast isa-build run-isa cov-test \
        coverage cosim linux-build linux-boot clean

all: lint tb isa-build run-isa coverage

lint:
	veryl fmt --check
	veryl check

veryl-build:
	veryl build

veryl-test:
	mkdir -p logs
	veryl test 2>&1 | tee logs/veryl_test.log

tb: veryl-build
	mkdir -p sim
	verilator --cc --exe --build -O2 --coverage --trace \
	    --top-module rv32ima_Core \
	    -Mdir sim/obj_dir -o tb_core \
	    target/rv_pkg.sv target/alu.sv target/core.sv tb/tb_core.cpp
	cp sim/obj_dir/tb_core $(SIM)

# Fast build without coverage/trace instrumentation (used for Linux boot).
tb-fast: veryl-build
	mkdir -p sim
	verilator --cc --exe --build -O3 -CFLAGS "-O2" \
	    --top-module rv32ima_Core \
	    -Mdir sim/obj_fast -o tb_core_fast \
	    target/rv_pkg.sv target/alu.sv target/core.sv tb/tb_core.cpp
	cp sim/obj_fast/tb_core_fast sim/tb_core_fast

isa-build:
	$(MAKE) -C $(TESTS_DIR) XLEN=32 RISCV_PREFIX=$(RISCV_PREFIX) $(TESTS)

run-isa:
	scripts/run_all_isa.sh

DIRECTED_TESTS := coverage_boost irq_test umode_test pmp_test

cov-test:
	mkdir -p sim logs/isa logs/cov
	for t in $(DIRECTED_TESTS); do \
	    $(RISCV_PREFIX)gcc -march=rv32g -mabi=ilp32 -static -mcmodel=medany \
	        -fvisibility=hidden -nostdlib -nostartfiles \
	        -Ithird_party/riscv-tests/env/p -Ithird_party/riscv-tests/isa/macros/scalar \
	        -Tthird_party/riscv-tests/env/p/link.ld \
	        tests/$$t.S -o sim/$$t.elf || exit 1; \
	    scripts/run_isa.sh sim/$$t.elf || { cat logs/isa/$$t.out; exit 1; }; \
	    cat logs/isa/$$t.out; \
	done

cosim:
	scripts/run_cosim.sh

coverage:
	mkdir -p logs/cov/annotated
	verilator_coverage --annotate logs/cov/annotated --annotate-min 1 \
	    logs/cov/*.dat 2>&1 | tee logs/cov/summary.txt

linux-build:
	linux/build_linux.sh

linux-boot: tb-fast
	scripts/run_linux.sh --batch

clean:
	rm -rf target sim logs
