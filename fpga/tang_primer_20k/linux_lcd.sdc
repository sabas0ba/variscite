# DDR and pixel clocks have independent PLL phase. Bound Gray-bus routing to
# less than the faster source period (10.101 ns); this also bounds bus skew.
create_generated_clock -name pixel -source [get_ports {i_clk}] -multiply_by 11 -divide_by 9 [get_pins {probe/lcd_clock_mode.clock_gen/pll/CLKOUT}]
set_max_delay -from [get_clocks {ddr_ctrl}] -to [get_clocks {pixel}] 9
set_max_delay -from [get_clocks {pixel}] -to [get_clocks {ddr_ctrl}] 9
set_false_path -hold -from [get_clocks {ddr_ctrl}] -to [get_clocks {pixel}]
set_false_path -hold -from [get_clocks {pixel}] -to [get_clocks {ddr_ctrl}]
# Sticky error synchronizer in the CPU domain. No multibit counter crosses.
set_max_delay -from [get_clocks {pixel}] -to [get_clocks {reference}] 30
set_false_path -hold -from [get_clocks {pixel}] -to [get_clocks {reference}]
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/linux_mode.linux_probe/display_mode.enable_sync_0_s0/D}]
