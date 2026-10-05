# Structural capability probe only; never program its output on a board.
set root [file normalize [file join [file dirname [info script]] ..]]
set_device -name GW2A-18C GW2A-LV18PG256C8/I7
add_file -type verilog [file join $root target tang_primer_20k ddr_gowin_probe.sv]
set_option -top_module rv32ima_TangDdrGowinProbe
set_option -verilog_std sysv2017
set_option -output_base_name ddr_capability
run syn
run pnr
