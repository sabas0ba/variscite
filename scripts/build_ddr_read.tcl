set root [file normalize [file join [file dirname [info script]] ..]]
set out [pwd]
set_device -name GW2A-18C GW2A-LV18PG256C8/I7
add_file -type verilog [file join $root target power_on_reset.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_clock.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr3_startup.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_phy_io.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_read_gate_sweep.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_read_delay_stepper.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_array_probe.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_burst_alignment.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_timeline.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_raw_burst.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_init_probe.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_phy_startup.sv]
add_file -type verilog [file join $root target tang_primer_20k ddr_read_probe.sv]
add_file -type cst [file join $out ddr_read.cst]
add_file -type sdc [file join $root fpga tang_primer_20k ddr_read_probe.sdc]
set_option -top_module rv32ima_TangDdrReadProbe
set_option -verilog_std sysv2017
set_option -output_base_name ddr_read
run syn
run pnr
