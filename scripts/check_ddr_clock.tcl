# Clock-only structural check; never program the generated output.
set root [file normalize [file join [file dirname [info script]] ..]]
set_device -name GW2A-18C GW2A-LV18PG256C8/I7
add_file -type verilog [file join $root target tang_primer_20k ddr_clock.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_clock_check.sv]
add_file -type cst [file join $root fpga tang_primer_20k ddr_clock_check.cst]
add_file -type sdc [file join $root fpga tang_primer_20k ddr_clock_check.sdc]
set_option -top_module rv32ima_TangDdrClockCheck
set_option -verilog_std sysv2017
set_option -output_base_name ddr_clock
run syn
run pnr
