# Standalone resource check only: no I/O placement or board bitstream.
set root [file normalize [file join [file dirname [info script]] ..]]
set_device -name GW2A-18C GW2A-LV18PG256C8/I7
foreach source {ddr_display_fifo ddr_frame_reader ddr_lcd_pixels lcd_timing ddr_lcd_stream} {
    add_file -type verilog [file join $root target tang_primer_20k $source.sv]
}
set_option -top_module $::env(DISPLAY_TOP)
set_option -verilog_std sysv2017
set_option -output_base_name $::env(DISPLAY_OUTPUT)
run syn
