SHELL := /bin/bash

RISCV_PREFIX ?= riscv-none-elf-
TESTS_DIR    := third_party/riscv-tests/isa
SIM          := sim/tb_core
TESTS        := $(shell scripts/list_tests.sh)
RTL          := target/rv_pkg.sv target/alu.sv target/core.sv target/clint.sv \
                target/plic.sv target/soc.sv

.PHONY: all lint veryl-build veryl-test plic-multi-test tb tb-fast isa-build \
        run-isa cov-test coverage cov-check cosim linux-build linux-boot clean

all: lint veryl-test plic-multi-test tb isa-build run-isa cov-test cov-check cosim

lint:
	veryl fmt --check
	veryl check

veryl-build:
	veryl build

veryl-test:
	mkdir -p logs
	veryl test 2>&1 | tee logs/veryl_test.log

# Built standalone with an explicit top: see the header of tb/tb_plic_multi.sv
# for why this one cannot go through `veryl test`.
plic-multi-test: veryl-build
	mkdir -p sim
	verilator --binary --timing -Wno-fatal \
	    --top-module tb_plic_multi \
	    -Mdir sim/obj_plic_multi -o plic_multi \
	    target/rv_pkg.sv target/plic.sv tb/tb_plic_multi.sv
	sim/obj_plic_multi/plic_multi

tb: veryl-build
	mkdir -p sim
	verilator --cc --exe --build -O2 --coverage --trace \
	    --top-module rv32ima_Soc \
	    -Mdir sim/obj_dir -o tb_core \
	    $(RTL) tb/tb_core.cpp
	cp sim/obj_dir/tb_core $(SIM)

# Fast build without coverage/trace instrumentation (used for Linux boot).
tb-fast: veryl-build
	mkdir -p sim
	verilator --cc --exe --build -O3 -CFLAGS "-O2" \
	    --top-module rv32ima_Soc \
	    -Mdir sim/obj_fast -o tb_core_fast \
	    $(RTL) tb/tb_core.cpp
	cp sim/obj_fast/tb_core_fast sim/tb_core_fast

isa-build:
	$(MAKE) -C $(TESTS_DIR) XLEN=32 RISCV_PREFIX=$(RISCV_PREFIX) $(TESTS)

run-isa:
	scripts/run_all_isa.sh

DIRECTED_TESTS := coverage_boost irq_test umode_test pmp_test clint_plic_test

# clint_plic_test runs with a divided mtime tick so that the CLINT counter is
# exercised on both the ticking and the idle cycle.

cov-test:
	mkdir -p sim logs/isa logs/cov
	for t in $(DIRECTED_TESTS); do \
	    $(RISCV_PREFIX)gcc -march=rv32g -mabi=ilp32 -static -mcmodel=medany \
	        -fvisibility=hidden -nostdlib -nostartfiles \
	        -Ithird_party/riscv-tests/env/p -Ithird_party/riscv-tests/isa/macros/scalar \
	        -Tthird_party/riscv-tests/env/p/link.ld \
	        tests/$$t.S -o sim/$$t.elf || exit 1; \
	    case $$t in \
	      clint_plic_test) extra="+mtimediv=3";; \
	      *)               extra="";; \
	    esac; \
	    scripts/run_isa.sh sim/$$t.elf $$extra || { cat logs/isa/$$t.out; exit 1; }; \
	    cat logs/isa/$$t.out; \
	done

cov-check: coverage
	scripts/cov_check.sh

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
