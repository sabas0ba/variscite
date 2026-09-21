SHELL := /bin/bash

RISCV_PREFIX ?= riscv-none-elf-
TESTS_DIR    := third_party/riscv-tests/isa
SIM          := sim/tb_core
TESTS        := $(shell scripts/list_tests.sh)
RTL          := target/rv_pkg.sv target/alu.sv target/core.sv target/clint.sv \
                target/plic.sv target/soc.sv

.PHONY: all lint veryl-build veryl-test plic-multi-test tb tb-fast isa-build \
        run-isa cov-test coverage cov-check cosim linux-build linux-boot \
        fpga-fw fpga-sim por-test lcd-test fpga-lcd fpga-tang fpga-tang-prog fpga-arty fpga-arty-prog clean

all: lint veryl-test plic-multi-test tb isa-build run-isa cov-test cov-check \
     cosim fpga-sim por-test lcd-test lcd-mmio-test lcd-reset-test lcd-soc-test \
     ddr3-startup-test ddr-word-cdc-test ddr-read-gate-test ddr-mpr-test ddr-mpr-delay-test

lint:
	@test -z "$$(find src fpga -type f \( -name '*.sv' -o -name '*.v' \))" || \
	    { echo 'RTL sources under src/ and fpga/ must be Veryl' >&2; exit 1; }
	veryl fmt --check
	veryl check

veryl-build:
	veryl build

veryl-test:
	mkdir -p logs
	set -o pipefail; veryl test src/*.veryl 2>&1 | tee logs/veryl_test.log

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

# --- FPGA ports ----------------------------------------------------------
.PHONY: ddr3-startup-test ddr-word-cdc-test ddr-read-gate-test ddr-mpr-test ddr-mpr-delay-test
ddr-mpr-delay-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_mpr_delay_sweep \
	    -Mdir sim/obj_ddr_mpr_delay_sweep -o tb_ddr_mpr_delay_sweep \
	    target/tang_primer_20k/ddr_read_delay_stepper.sv \
	    target/tang_primer_20k/ddr_read_gate_sweep.sv tb/tb_ddr_mpr_delay_sweep.sv
	sim/obj_ddr_mpr_delay_sweep/tb_ddr_mpr_delay_sweep

ddr-mpr-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_mpr_sweep \
	    -Mdir sim/obj_ddr_mpr_sweep -o tb_ddr_mpr_sweep \
	    target/tang_primer_20k/ddr_read_gate_sweep.sv tb/tb_ddr_mpr_sweep.sv
	sim/obj_ddr_mpr_sweep/tb_ddr_mpr_sweep

ddr-read-gate-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_read_gate_sweep \
	    -Mdir sim/obj_ddr_read_gate_sweep -o tb_ddr_read_gate_sweep \
	    target/tang_primer_20k/ddr_read_gate_sweep.sv tb/tb_ddr_read_gate_sweep.sv
	sim/obj_ddr_read_gate_sweep/tb_ddr_read_gate_sweep

ddr-word-cdc-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_word_cdc \
	    -Mdir sim/obj_ddr_word_cdc -o tb_ddr_word_cdc \
	    target/tang_primer_20k/ddr_word_cdc.sv tb/tb_ddr_word_cdc.sv
	sim/obj_ddr_word_cdc/tb_ddr_word_cdc
	sim/obj_ddr_word_cdc/tb_ddr_word_cdc +cpu_half=3 +mem_half=11
	sim/obj_ddr_word_cdc/tb_ddr_word_cdc +cpu_half=13 +mem_half=2

ddr3-startup-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr3_startup \
	    -Mdir sim/obj_ddr3_startup -o tb_ddr3_startup \
	    target/tang_primer_20k/ddr3_startup.sv tb/tb_ddr3_startup.sv
	sim/obj_ddr3_startup/tb_ddr3_startup
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr3_startup \
	    -GREAL_TIMING=1 -Mdir sim/obj_ddr3_startup_real -o tb_ddr3_startup \
	    target/tang_primer_20k/ddr3_startup.sv tb/tb_ddr3_startup.sv
	sim/obj_ddr3_startup_real/tb_ddr3_startup

# The board top names sim/fpga/firmware.hex as RAM_INIT, and $$readmemh
# resolves it against the working directory, so these run from the repo root.

FPGA_RTL := target/rv_pkg.sv target/alu.sv target/core.sv target/clint.sv \
            target/plic.sv target/soc.sv target/uart.sv target/ram.sv \
            target/power_on_reset.sv target/fpga_soc.sv

fpga-fw:
	scripts/build_fw.sh

por-test: veryl-build
	bash scripts/test_por.sh

lcd-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_lcd \
	    -Mdir sim/obj_lcd -o tb_lcd target/tang_primer_20k/lcd_timing.sv tb/tb_lcd.sv
	sim/obj_lcd/tb_lcd

fpga-lcd:
	bash scripts/build_lcd.sh

.PHONY: lcd-mmio-test lcd-reset-test lcd-soc-test fpga-lcd-soc
lcd-reset-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_lcd_reset \
	    -Mdir sim/obj_lcd_reset -o tb_lcd_reset target/tang_primer_20k/lcd_clock.sv tb/tb_lcd_reset.sv
	sim/obj_lcd_reset/tb_lcd_reset

lcd-mmio-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_lcd_mmio \
	    -Mdir sim/obj_lcd_mmio -o tb_lcd_mmio target/tang_primer_20k/lcd_mmio.sv tb/tb_lcd_mmio.sv
	sim/obj_lcd_mmio/tb_lcd_mmio
	sim/obj_lcd_mmio/tb_lcd_mmio +cpu_half=11 +pixel_half=3
	sim/obj_lcd_mmio/tb_lcd_mmio +cpu_half=3 +pixel_half=13

fpga-lcd-soc:
	bash scripts/build_lcd_soc.sh

lcd-soc-test: veryl-build fpga-fw
	verilator --cc --exe --build -O2 --top-module rv32ima_TangLcdSystem \
	    -GCLK_HZ=1000000 -GUART_DIV=2 -CFLAGS -DLCD_SYSTEM \
	    -Mdir sim/obj_lcd_soc -o tb_lcd_soc $(FPGA_RTL) \
	    target/tang_primer_20k/lcd_timing.sv target/tang_primer_20k/lcd_mmio.sv \
	    target/tang_primer_20k/lcd_system.sv tb/tb_fpga.cpp
	sim/obj_lcd_soc/tb_lcd_soc +cycles=8000000 +bitcycles=32 +send=Z +expect="[lcd] applied"

# Board-independent check of the FPGA platform: the firmware runs on FpgaSoc
# and the console is decoded off the serial line, so a broken UART, RAM or
# boot stub fails here rather than on the bench. The clock and divisor are
# scaled down so a simulated second is reachable.
fpga-sim: veryl-build fpga-fw
	mkdir -p sim
	verilator --cc --exe --build -O2 --top-module rv32ima_FpgaSoc \
	    -GCLK_HZ=1000000 -GUART_DIV=2 -GRAM_INIT='"sim/fpga/firmware.hex"' \
	    -Mdir sim/obj_fpga -o tb_fpga \
	    $(FPGA_RTL) tb/tb_fpga.cpp
	sim/obj_fpga/tb_fpga +cycles=4000000 +bitcycles=32 +send="Hi!" \
	    +expect="[tick] 2"

fpga-tang:
	scripts/build_fpga.sh tang

fpga-tang-prog:
	scripts/build_fpga.sh tang --prog

fpga-arty:
	scripts/build_fpga.sh arty

fpga-arty-prog:
	scripts/build_fpga.sh arty --prog

linux-build:
	linux/build_linux.sh

linux-boot: tb-fast
	scripts/run_linux.sh --batch

clean:
	rm -rf target sim logs
