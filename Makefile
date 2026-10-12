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

all: lint veryl-test plic-multi-test core-bus-error-test linux-console-test tb isa-build run-isa cov-test cov-check \
     cosim fpga-sim por-test lcd-test lcd-mmio-test lcd-reset-test lcd-soc-test \
     ddr3-startup-test ddr-word-cdc-test ddr-read-gate-test ddr-mpr-test ddr-mpr-delay-test ddr-status-uart-test \
     ddr-burst-controller-test ddr-controller-probe-test ddr-display-test tang-lcd-boot-test \
     usb-host-test usb-hid-test sd-spi-test sd-boot-test tang-sd-boot-test

lint:
	@test -z "$$(find src fpga -type f \( -name '*.sv' -o -name '*.v' \))" || \
	    { echo 'RTL sources under src/ and fpga/ must be Veryl' >&2; exit 1; }
	veryl fmt --check
	veryl check

.PHONY: core-bus-error-test
.PHONY: ddr-cpu-port-test
ddr-cpu-port-test: veryl-build
	FULL_WORDS=64 HOLD_CYCLES=1000 OUTPUT_NAME=ddr_cpu_test bash scripts/build_ddr_cpu.sh
	for ratio in '19 5' '5 19' '7 11'; do \
	    set -- $$ratio; \
	    verilator --binary --timing -Wno-fatal --top-module tb_ddr_cpu_port \
	    -GCPU_HALF=$$1 -GMEM_HALF=$$2 \
	    -Mdir sim/obj_ddr_cpu_port -o ddr_cpu_port \
	    $(RTL) target/ram.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_cpu_port.sv \
	    tb/tb_ddr_cpu_port.sv || exit 1; \
	    sim/obj_ddr_cpu_port/ddr_cpu_port || exit 1; \
	done

core-bus-error-test: veryl-build
	mkdir -p sim logs/cov
	verilator --cc --exe --build --coverage --trace --top-module rv32ima_Soc \
	    -Mdir sim/obj_core_bus_error -o core_bus_error \
	    $(RTL) tb/tb_core_bus_error.cpp
	sim/obj_core_bus_error/core_bus_error

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

cov-test: core-bus-error-test
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
.PHONY: ddr-burst-controller-test
.PHONY: ddr-controller-probe-test
.PHONY: ddr-word-probe-test
.PHONY: ddr-full-probe-test ddr-training-diagnostic-test
ddr-training-diagnostic-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_training_diagnostic \
	    -Mdir sim/obj_ddr_training_diagnostic -o tb_ddr_training_diagnostic \
	    target/tang_primer_20k/ddr_training_diagnostic.sv tb/tb_ddr_training_diagnostic.sv
	sim/obj_ddr_training_diagnostic/tb_ddr_training_diagnostic

ddr-full-probe-test: veryl-build ddr-training-diagnostic-test
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_full_probe \
	    -Mdir sim/obj_ddr_full_probe -o tb_ddr_full_probe \
	    target/tang_primer_20k/ddr_word_cdc.sv target/tang_primer_20k/ddr_word_port.sv \
	    target/tang_primer_20k/ddr_burst_controller.sv target/tang_primer_20k/ddr_word_probe.sv tb/tb_ddr_full_probe.sv
	sim/obj_ddr_full_probe/tb_ddr_full_probe
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_full_probe -GMIXED=1 \
	    -Mdir sim/obj_ddr_full_mixed_probe -o tb_ddr_full_mixed_probe \
	    target/tang_primer_20k/ddr_word_cdc.sv target/tang_primer_20k/ddr_word_port.sv \
	    target/tang_primer_20k/ddr_burst_controller.sv target/tang_primer_20k/ddr_word_probe.sv tb/tb_ddr_full_probe.sv
	sim/obj_ddr_full_mixed_probe/tb_ddr_full_mixed_probe

ddr-word-probe-test: veryl-build ddr-full-probe-test
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_word_probe \
	    -Mdir sim/obj_ddr_word_probe -o tb_ddr_word_probe \
	    target/tang_primer_20k/ddr_word_cdc.sv target/tang_primer_20k/ddr_word_port.sv \
	    target/tang_primer_20k/ddr_burst_controller.sv target/tang_primer_20k/ddr_word_probe.sv tb/tb_ddr_word_probe.sv
	sim/obj_ddr_word_probe/tb_ddr_word_probe

.PHONY: tang-boot-test ddr-cpu-access-test
.PHONY: tang-lcd-boot-test
tang-lcd-boot-test: veryl-build
	WITH_LCD=1 bash scripts/build_tang_boot.sh
	riscv-none-elf-gcc -DWITH_LCD=1 -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
	    -Wl,-Ttext=0x80000000,-e,_start,--build-id=none tests/tang_boot_payload.S -o sim/tang_boot_lcd_payload.elf
	riscv-none-elf-objcopy -O binary sim/tang_boot_lcd_payload.elf sim/tang_boot_lcd_payload.bin
	verilator --cc --exe --build -Wno-fatal --top-module rv32ima_DdrLinuxSoc \
	    -GWITH_LCD=1 '-GROM_INIT="sim/tang_boot_lcd.hex"' \
	    -Mdir sim/obj_tang_lcd_boot -o tang_lcd_boot \
	    $(RTL) target/ram.sv target/uart.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_linux_soc.sv \
	    $(CURDIR)/tb/tb_tang_boot.cpp
	sim/obj_tang_lcd_boot/tang_lcd_boot 240 lcd
	verilator --cc --exe --build -Wno-fatal --top-module tb_tang_cached_boot \
	    -CFLAGS -DCACHED_BOOT -Mdir sim/obj_tang_cached_boot -o tang_cached_boot \
	    $(RTL) target/ram.sv target/uart.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_linux_soc.sv \
	    target/tang_primer_20k/ddr_burst_read_cache.sv tb/tb_tang_cached_boot.sv \
	    $(CURDIR)/tb/tb_tang_boot.cpp
	sim/obj_tang_cached_boot/tang_cached_boot 240 lcd
	verilator --cc --exe --build -Wno-fatal --top-module tb_tang_cached_boot -GWITH_IO=1 \
	    -CFLAGS -DCACHED_BOOT -Mdir sim/obj_tang_io_boot -o tang_io_boot \
	    $(RTL) target/ram.sv target/uart.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_linux_soc.sv \
	    target/tang_primer_20k/ddr_burst_read_cache.sv tb/tb_tang_cached_boot.sv \
	    $(CURDIR)/tb/tb_tang_boot.cpp
	sim/obj_tang_io_boot/tang_io_boot 240 lcd

tang-boot-test: veryl-build
	bash scripts/build_tang_boot.sh
	riscv-none-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
	    -Wl,-Ttext=0x80000000,-e,_start,--build-id=none tests/tang_boot_payload.S -o sim/tang_boot_payload.elf
	riscv-none-elf-objcopy -O binary sim/tang_boot_payload.elf sim/tang_boot_payload.bin
	verilator --cc --exe --build -Wno-fatal --top-module rv32ima_DdrLinuxSoc \
	    -Mdir sim/obj_tang_boot -o tang_boot \
	    $(RTL) target/ram.sv target/uart.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_linux_soc.sv \
	    $(CURDIR)/tb/tb_tang_boot.cpp
	sim/obj_tang_boot/tang_boot
	sim/obj_tang_boot/tang_boot 234
	sim/obj_tang_boot/tang_boot 246

ddr-cpu-access-test: veryl-build
	CPU_PROGRAM=access bash scripts/build_ddr_cpu.sh
	verilator --binary --timing -Wno-fatal --top-module tb_ddr_cpu_access \
	    -Mdir sim/obj_ddr_cpu_access -o ddr_cpu_access \
	    $(RTL) target/ram.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_cpu_port.sv \
	    target/tang_primer_20k/ddr_burst_controller.sv target/tang_primer_20k/ddr_cpu_probe.sv \
	    tb/tb_ddr_cpu_access.sv
	sim/obj_ddr_cpu_access/ddr_cpu_access

.PHONY: ddr-cpu-probe-test
ddr-cpu-probe-test: veryl-build
	FULL_WORDS=64 HOLD_CYCLES=1000 OUTPUT_NAME=ddr_cpu_test bash scripts/build_ddr_cpu.sh
	verilator --binary --timing -Wno-fatal --top-module tb_ddr_cpu_probe \
	    -Mdir sim/obj_ddr_cpu_probe -o ddr_cpu_probe \
	    $(RTL) target/ram.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_cpu_port.sv \
	    target/tang_primer_20k/ddr_burst_controller.sv target/tang_primer_20k/ddr_cpu_probe.sv \
	    tb/tb_ddr_cpu_probe.sv
	sim/obj_ddr_cpu_probe/ddr_cpu_probe

ddr-controller-probe-test: veryl-build ddr-word-probe-test ddr-cpu-port-test ddr-cpu-probe-test ddr-cpu-access-test tang-boot-test
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_controller_probe \
	    -Mdir sim/obj_ddr_controller_probe -o tb_ddr_controller_probe \
	    target/tang_primer_20k/ddr_burst_controller.sv target/tang_primer_20k/ddr_controller_probe.sv tb/tb_ddr_controller_probe.sv
	sim/obj_ddr_controller_probe/tb_ddr_controller_probe

ddr-burst-controller-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_burst_controller \
	    -Mdir sim/obj_ddr_burst_controller -o tb_ddr_burst_controller \
	    target/tang_primer_20k/ddr_burst_controller.sv tb/tb_ddr_burst_controller.sv
	sim/obj_ddr_burst_controller/tb_ddr_burst_controller

.PHONY: ddr-display-test
.PHONY: usb-ulpi-test usb-host-test usb-hid-test
.PHONY: sd-boot-test sd-spi-test
.PHONY: tang-sd-boot-test
tang-sd-boot-test: veryl-build
	WITH_SD=1 bash scripts/build_tang_boot.sh
	riscv-none-elf-gcc -DWITH_LCD=1 -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
	    -Wl,-Ttext=0x80000000,-e,_start,--build-id=none tests/tang_boot_payload.S -o sim/tang_boot_lcd_payload.elf
	riscv-none-elf-objcopy -O binary sim/tang_boot_lcd_payload.elf sim/tang_boot_lcd_payload.bin
	verilator --cc --exe --build -Wno-fatal --top-module tb_tang_cached_boot -GWITH_IO=1 -GWITH_SD=1 \
	    -CFLAGS '-DCACHED_BOOT -DSD_BOOT' -Mdir sim/obj_tang_sd_boot -o tang_sd_boot \
	    $(RTL) target/ram.sv target/uart.sv target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv target/tang_primer_20k/ddr_linux_soc.sv \
	    target/tang_primer_20k/sd_spi_mmio.sv target/tang_primer_20k/ddr_burst_read_cache.sv \
	    tb/tb_tang_cached_boot.sv $(CURDIR)/tb/tb_tang_boot.cpp
	sim/obj_tang_sd_boot/tang_sd_boot 240 lcd
	sim/obj_tang_sd_boot/tang_sd_boot 240 lcd bad-crc
	sim/obj_tang_sd_boot/tang_sd_boot 240 lcd bad-sector

sd-boot-test:
	mkdir -p sim
	$(CC) -std=c11 -Wall -Wextra -Werror -Ifpga/firmware \
	    fpga/firmware/sd_fat.c tests/sd_fat_test.c -o sim/sd_fat_test
	sim/sd_fat_test

sd-spi-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_sd_spi_mmio \
	    -Mdir sim/obj_sd_spi_mmio -o tb_sd_spi_mmio \
	    target/tang_primer_20k/sd_spi_mmio.sv tb/tb_sd_spi_mmio.sv
	sim/obj_sd_spi_mmio/tb_sd_spi_mmio

usb-hid-test:
	mkdir -p sim
	$(CC) -std=c11 -Wall -Wextra -Werror -Ilinux/user \
	    linux/user/usb_hid.c tests/usb_hid_test.c -o sim/usb_hid_test
	sim/usb_hid_test
	$(CC) -std=c11 -Wall -Wextra -Werror -Ilinux/user \
	    linux/user/usb_hid.c tests/usb_hub_test.c -o sim/usb_hub_test
	sim/usb_hub_test

usb-host-test: veryl-build usb-ulpi-test
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_usb_ulpi_input \
	    -Mdir sim/obj_usb_ulpi_input -o tb_usb_ulpi_input \
	    target/tang_primer_20k/usb_ulpi_input.sv target/tang_primer_20k/usb_ulpi_link.sv tb/tb_usb_ulpi_input.sv
	sim/obj_usb_ulpi_input/tb_usb_ulpi_input
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_usb_host_transaction \
	    -Mdir sim/obj_usb_host_transaction -o tb_usb_host_transaction \
	    target/tang_primer_20k/usb_ulpi_link.sv target/tang_primer_20k/usb_host_transaction.sv \
	    tb/tb_usb_host_transaction.sv
	sim/obj_usb_host_transaction/tb_usb_host_transaction
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_usb_host_mmio \
	    -Mdir sim/obj_usb_host_mmio -o tb_usb_host_mmio \
	    target/tang_primer_20k/usb_ulpi_link.sv target/tang_primer_20k/usb_host_transaction.sv \
	    target/tang_primer_20k/usb_host_mmio.sv tb/tb_usb_host_mmio.sv
	sim/obj_usb_host_mmio/tb_usb_host_mmio

usb-ulpi-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_usb_ulpi_link \
	    -Mdir sim/obj_usb_ulpi_link -o tb_usb_ulpi_link \
	    target/tang_primer_20k/usb_ulpi_link.sv tb/tb_usb_ulpi_link.sv
	sim/obj_usb_ulpi_link/tb_usb_ulpi_link

ddr-display-test: veryl-build ddr-display-fifo-test ddr-lcd-pixels-test ddr-lcd-stream-test ddr-burst-cache-test
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_display \
	    -Mdir sim/obj_ddr_display -o tb_ddr_display \
	    target/tang_primer_20k/ddr_burst_arbiter.sv target/tang_primer_20k/ddr_frame_reader.sv \
	    target/tang_primer_20k/ddr_display_fifo.sv target/tang_primer_20k/ddr_burst_controller.sv tb/tb_ddr_display.sv
	sim/obj_ddr_display/tb_ddr_display

.PHONY: ddr-burst-cache-test
ddr-burst-cache-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_burst_read_cache \
	    -Mdir sim/obj_ddr_burst_read_cache -o tb_ddr_burst_read_cache \
	    target/tang_primer_20k/ddr_burst_read_cache.sv tb/tb_ddr_burst_read_cache.sv
	sim/obj_ddr_burst_read_cache/tb_ddr_burst_read_cache

.PHONY: ddr-lcd-stream-test
ddr-lcd-stream-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_lcd_stream \
	    -Mdir sim/obj_ddr_lcd_stream -o tb_ddr_lcd_stream \
	    target/tang_primer_20k/ddr_lcd_stream.sv target/tang_primer_20k/ddr_burst_arbiter.sv \
	    target/tang_primer_20k/ddr_frame_reader.sv target/tang_primer_20k/ddr_display_fifo.sv \
	    target/tang_primer_20k/ddr_lcd_pixels.sv target/tang_primer_20k/lcd_timing.sv \
	    target/tang_primer_20k/ddr_burst_read_cache.sv target/tang_primer_20k/ddr_burst_controller.sv tb/tb_ddr_lcd_stream.sv
	sim/obj_ddr_lcd_stream/tb_ddr_lcd_stream
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_lcd_stream -GCACHE=1 \
	    -Mdir sim/obj_ddr_lcd_cached_stream -o tb_ddr_lcd_cached_stream \
	    target/tang_primer_20k/ddr_lcd_stream.sv target/tang_primer_20k/ddr_burst_arbiter.sv \
	    target/tang_primer_20k/ddr_frame_reader.sv target/tang_primer_20k/ddr_display_fifo.sv \
	    target/tang_primer_20k/ddr_lcd_pixels.sv target/tang_primer_20k/lcd_timing.sv \
	    target/tang_primer_20k/ddr_burst_read_cache.sv target/tang_primer_20k/ddr_burst_controller.sv tb/tb_ddr_lcd_stream.sv
	sim/obj_ddr_lcd_cached_stream/tb_ddr_lcd_cached_stream

.PHONY: ddr-lcd-pixels-test
ddr-lcd-pixels-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_lcd_pixels \
	    -Mdir sim/obj_ddr_lcd_pixels -o tb_ddr_lcd_pixels \
	    target/tang_primer_20k/lcd_timing.sv target/tang_primer_20k/ddr_lcd_pixels.sv tb/tb_ddr_lcd_pixels.sv
	sim/obj_ddr_lcd_pixels/tb_ddr_lcd_pixels

.PHONY: ddr-display-fifo-test
ddr-display-fifo-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_display_fifo \
	    -Mdir sim/obj_ddr_display_fifo -o tb_ddr_display_fifo \
	    target/tang_primer_20k/ddr_display_fifo.sv tb/tb_ddr_display_fifo.sv
	sim/obj_ddr_display_fifo/tb_ddr_display_fifo
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_display_fifo -GMEM_HALF=19 -GPIXEL_HALF=5 \
	    -Mdir sim/obj_ddr_display_fifo_slow -o tb_ddr_display_fifo \
	    target/tang_primer_20k/ddr_display_fifo.sv tb/tb_ddr_display_fifo.sv
	sim/obj_ddr_display_fifo_slow/tb_ddr_display_fifo
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_display_fifo -GMEM_HALF=7 -GPIXEL_HALF=11 \
	    -Mdir sim/obj_ddr_display_fifo_phase -o tb_ddr_display_fifo \
	    target/tang_primer_20k/ddr_display_fifo.sv tb/tb_ddr_display_fifo.sv
	sim/obj_ddr_display_fifo_phase/tb_ddr_display_fifo

.PHONY: ddr3-startup-test ddr-word-cdc-test ddr-read-gate-test ddr-mpr-test ddr-mpr-delay-test ddr-mpr-align-test ddr-array-test ddr-array-simple-test ddr-array-early-test ddr-array-gate-test ddr-array-early-scan-test ddr-array-same-test ddr-timeline-test ddr-full-timeline-test ddr-status-uart-test

.PHONY: ddr-array-phase-test
.PHONY: ddr-phy-startup-test
.PHONY: ddr-read-assembler-test
.PHONY: ddr-read-training-test
.PHONY: ddr-trained-array-test
.PHONY: ddr-multi-array-test
.PHONY: ddr-retain-array-test
.PHONY: ddr-mask-array-test
.PHONY: ddr-address-array-test
ddr-address-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_address_array \
	    -Mdir sim/obj_ddr_address_array -o tb_ddr_address_array \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_address_array.sv
	sim/obj_ddr_address_array/tb_ddr_address_array

ddr-mask-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_mask_array \
	    -Mdir sim/obj_ddr_mask_array -o tb_ddr_mask_array \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_mask_array.sv
	sim/obj_ddr_mask_array/tb_ddr_mask_array

.PHONY: ddr-refresh-array-test ddr-refresh-duration-test
ddr-refresh-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GMULTI=1 -GRETAIN=1 -GREFRESH=4 --top-module tb_ddr_trained_array \
	    -Mdir sim/obj_ddr_refresh_array -o tb_ddr_refresh_array \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_trained_array.sv
	sim/obj_ddr_refresh_array/tb_ddr_refresh_array

ddr-refresh-duration-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GMULTI=1 -GRETAIN=1 -GREFRESH=32768 -GCASES=1 --top-module tb_ddr_trained_array \
	    -Mdir sim/obj_ddr_refresh_duration -o tb_ddr_refresh_duration \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_trained_array.sv
	sim/obj_ddr_refresh_duration/tb_ddr_refresh_duration

ddr-retain-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GMULTI=1 -GRETAIN=1 --top-module tb_ddr_trained_array \
	    -Mdir sim/obj_ddr_retain_array -o tb_ddr_retain_array \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_trained_array.sv
	sim/obj_ddr_retain_array/tb_ddr_retain_array

ddr-multi-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GMULTI=1 --top-module tb_ddr_trained_array \
	    -Mdir sim/obj_ddr_multi_array -o tb_ddr_multi_array \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_trained_array.sv
	sim/obj_ddr_multi_array/tb_ddr_multi_array

ddr-trained-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_trained_array \
	    -Mdir sim/obj_ddr_trained_array -o tb_ddr_trained_array \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_trained_array.sv
	sim/obj_ddr_trained_array/tb_ddr_trained_array

ddr-read-training-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_read_training \
	    -Mdir sim/obj_ddr_read_training -o tb_ddr_read_training \
	    target/tang_primer_20k/ddr_read_training.sv target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_read_training.sv
	sim/obj_ddr_read_training/tb_ddr_read_training

ddr-read-assembler-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_read_assembler \
	    -Mdir sim/obj_ddr_read_assembler -o tb_ddr_read_assembler \
	    target/tang_primer_20k/ddr_read_assembler.sv tb/tb_ddr_read_assembler.sv
	sim/obj_ddr_read_assembler/tb_ddr_read_assembler

.PHONY: ddr-raw-burst-test
ddr-raw-burst-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_raw_burst \
	    -Mdir sim/obj_ddr_raw_burst -o tb_ddr_raw_burst \
	    target/tang_primer_20k/ddr_raw_burst.sv tb/tb_ddr_raw_burst.sv
	sim/obj_ddr_raw_burst/tb_ddr_raw_burst

ddr-phy-startup-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_phy_startup \
	    -Mdir sim/obj_ddr_phy_startup -o tb_ddr_phy_startup \
	    target/tang_primer_20k/ddr_phy_startup.sv tb/tb_ddr_phy_startup.sv
	sim/obj_ddr_phy_startup/tb_ddr_phy_startup

.PHONY: ddr-array-phase-scan-test
.PHONY: ddr-array-continuous-test
.PHONY: ddr-array-aligned-scan-test
ddr-array-aligned-scan-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GPHASE_SCAN=1 -GREAD_HOLD=0 -GPHASE_ALIGN=1 --top-module tb_ddr_array_gate_scan \
	    -Mdir sim/obj_ddr_array_aligned_scan -o tb_ddr_array_aligned_scan \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_gate_scan.sv
	sim/obj_ddr_array_aligned_scan/tb_ddr_array_aligned_scan

ddr-array-continuous-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GPHASE_SCAN=1 -GREAD_HOLD=0 --top-module tb_ddr_array_gate_scan \
	    -Mdir sim/obj_ddr_array_continuous -o tb_ddr_array_continuous \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_gate_scan.sv
	sim/obj_ddr_array_continuous/tb_ddr_array_continuous

ddr-array-phase-scan-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GPHASE_SCAN=1 --top-module tb_ddr_array_gate_scan \
	    -Mdir sim/obj_ddr_array_phase_scan -o tb_ddr_array_phase_scan \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_gate_scan.sv
	sim/obj_ddr_array_phase_scan/tb_ddr_array_phase_scan

.PHONY: ddr-alignment-test
ddr-alignment-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_alignment \
	    -Mdir sim/obj_ddr_alignment -o tb_ddr_alignment \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_timeline.sv tb/tb_ddr_alignment.sv
	sim/obj_ddr_alignment/tb_ddr_alignment

ddr-array-phase-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps "-GREAD_SEL=6'h24" --top-module tb_ddr_array_probe \
	    -Mdir sim/obj_ddr_array_phase -o tb_ddr_array_phase \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_probe.sv
	sim/obj_ddr_array_phase/tb_ddr_array_phase

ddr-expected-timeline-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_expected_timeline \
	    -Mdir sim/obj_ddr_expected_timeline -o tb_ddr_expected_timeline \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_timeline.sv tb/tb_ddr_expected_timeline.sv
	sim/obj_ddr_expected_timeline/tb_ddr_expected_timeline

.PHONY: ddr-expected-timeline-test

ddr-full-timeline-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GMATCH_ALL=1 --top-module tb_ddr_timeline \
	    -Mdir sim/obj_ddr_full_timeline -o tb_ddr_full_timeline \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_timeline.sv tb/tb_ddr_timeline.sv
	sim/obj_ddr_full_timeline/tb_ddr_full_timeline

ddr-array-early-scan-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -GEARLY_GATE=1 --top-module tb_ddr_array_gate_scan \
	    -Mdir sim/obj_ddr_array_early_scan -o tb_ddr_array_early_scan \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_gate_scan.sv
	sim/obj_ddr_array_early_scan/tb_ddr_array_early_scan

ddr-array-early-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -DSIMPLE_DATA -DEARLY_GATE --top-module tb_ddr_array_probe \
	    -Mdir sim/obj_ddr_array_early -o tb_ddr_array_early \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_probe.sv
	sim/obj_ddr_array_early/tb_ddr_array_early

ddr-array-simple-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps -DSIMPLE_DATA --top-module tb_ddr_array_probe \
	    -Mdir sim/obj_ddr_array_simple -o tb_ddr_array_simple \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_probe.sv
	sim/obj_ddr_array_simple/tb_ddr_array_simple

ddr-timeline-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_timeline \
	    -Mdir sim/obj_ddr_timeline -o tb_ddr_timeline \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_timeline.sv tb/tb_ddr_timeline.sv
	sim/obj_ddr_timeline/tb_ddr_timeline

ddr-array-same-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_array_gate_scan \
	    -GSAME_DATA=1 -Mdir sim/obj_ddr_array_same -o tb_ddr_array_same \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_gate_scan.sv
	sim/obj_ddr_array_same/tb_ddr_array_same

ddr-array-gate-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_array_gate_scan \
	    -Mdir sim/obj_ddr_array_gate_scan -o tb_ddr_array_gate_scan \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_gate_scan.sv
	sim/obj_ddr_array_gate_scan/tb_ddr_array_gate_scan

ddr-array-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_array_probe \
	    -Mdir sim/obj_ddr_array_probe -o tb_ddr_array_probe \
	    target/tang_primer_20k/ddr_burst_alignment.sv target/tang_primer_20k/ddr_array_probe.sv tb/tb_ddr_array_probe.sv
	sim/obj_ddr_array_probe/tb_ddr_array_probe
ddr-status-uart-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_status_uart \
	    -Mdir sim/obj_ddr_status_uart -o tb_ddr_status_uart \
	    target/tang_primer_20k/ddr_init_probe.sv tb/tb_ddr_status_uart.sv
	sim/obj_ddr_status_uart/tb_ddr_status_uart
	verilator --binary --timing --timescale 1ns/1ps -GFRAMED=1 --top-module tb_ddr_status_uart \
	    -Mdir sim/obj_ddr_status_uart_framed -o tb_ddr_status_uart_framed \
	    target/tang_primer_20k/ddr_init_probe.sv tb/tb_ddr_status_uart.sv
	sim/obj_ddr_status_uart_framed/tb_ddr_status_uart_framed
	verilator --binary --timing --timescale 1ns/1ps -GFRAMED=1 -GWIDE=1 --top-module tb_ddr_status_uart \
	    -Mdir sim/obj_ddr_status_uart_wide -o tb_ddr_status_uart_wide \
	    target/tang_primer_20k/ddr_init_probe.sv tb/tb_ddr_status_uart.sv
	sim/obj_ddr_status_uart_wide/tb_ddr_status_uart_wide
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_status_uart -GFRAMED=1 -GWIDE=1 -GSTREAM=1 \
	    -Mdir sim/obj_ddr_status_uart_stream -o tb_ddr_status_uart_stream \
	    target/tang_primer_20k/ddr_init_probe.sv tb/tb_ddr_status_uart.sv
	sim/obj_ddr_status_uart_stream/tb_ddr_status_uart_stream

ddr-mpr-delay-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_mpr_delay_sweep \
	    -Mdir sim/obj_ddr_mpr_delay_sweep -o tb_ddr_mpr_delay_sweep \
	    target/tang_primer_20k/ddr_read_delay_stepper.sv \
	    target/tang_primer_20k/ddr_read_gate_sweep.sv tb/tb_ddr_mpr_delay_sweep.sv
	sim/obj_ddr_mpr_delay_sweep/tb_ddr_mpr_delay_sweep

ddr-mpr-align-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_mpr_align_sweep \
	    -Mdir sim/obj_ddr_mpr_align_sweep -o tb_ddr_mpr_align_sweep \
	    target/tang_primer_20k/ddr_read_delay_stepper.sv \
	    target/tang_primer_20k/ddr_read_gate_sweep.sv tb/tb_ddr_mpr_align_sweep.sv
	sim/obj_ddr_mpr_align_sweep/tb_ddr_mpr_align_sweep

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

.PHONY: ddr-cdc-controller-test
ddr-cdc-controller-test: veryl-build
	verilator --binary --timing --timescale 1ns/1ps --top-module tb_ddr_cdc_controller \
	    -Mdir sim/obj_ddr_cdc_controller -o tb_ddr_cdc_controller \
	    target/tang_primer_20k/ddr_word_cdc.sv \
	    target/tang_primer_20k/ddr_word_port.sv \
	    target/tang_primer_20k/ddr_burst_controller.sv tb/tb_ddr_cdc_controller.sv
	sim/obj_ddr_cdc_controller/tb_ddr_cdc_controller
	sim/obj_ddr_cdc_controller/tb_ddr_cdc_controller +cpu_half=3 +mem_half=11
	sim/obj_ddr_cdc_controller/tb_ddr_cdc_controller +cpu_half=13 +mem_half=2

ddr-word-cdc-test: veryl-build ddr-cdc-controller-test
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

.PHONY: linux-lcd-build linux-lcd-boot
.PHONY: linux-standalone-build
linux-standalone-build:
	WITH_SD=1 bash scripts/build_tang_boot.sh
	WITH_LCD=1 WITH_USB=1 LINUX_OUT="$(CURDIR)/sim/linux-standalone" linux/build_linux.sh
	python3 scripts/pack_tang_boot.py sim/linux-standalone/Image \
	    sim/linux-standalone/tang_primer_20k_lcd.dtb sim/linux-standalone/TANGBOOT.VBL

linux-lcd-build:
	WITH_LCD=1 LINUX_OUT="$(CURDIR)/sim/linux-lcd-gui" linux/build_linux.sh

linux-lcd-boot: tb-fast linux-console-test
	mkdir -p logs/linux
	rm -f $(foreach n,0 1 2,logs/linux/fbui-$(n).rgb565 logs/linux/fbui-$(n).png)
	python3 scripts/linux_console_test.py --lcd-gui sim/tb_core_fast \
	    +kernel=sim/linux-lcd-gui/Image +dtb=sim/linux-lcd-gui/tang_primer_20k_lcd.dtb \
	    +ramsize_mb=128 +mtimediv=64 +timeout=8000000000 \
	    +conlog=logs/linux/lcd-gui-console.log +fb_capture=logs/linux/fbui
	python3 scripts/check_fbui_capture.py logs/linux/fbui

.PHONY: linux-console-test
linux-console-test:
	python3 tests/test_linux_console_test.py

linux-boot: tb-fast linux-console-test
	scripts/run_linux.sh --batch

clean:
	rm -rf target sim logs
