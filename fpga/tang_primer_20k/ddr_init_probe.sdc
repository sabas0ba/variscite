create_clock -name reference -period 37.037037 [get_ports {i_clk}]
create_generated_clock -name ddr_fast -source [get_ports {i_clk}] -multiply_by 44 -divide_by 3 [get_pins {clocks/pll/CLKOUT}]
create_generated_clock -name ddr_ctrl -source [get_pins {clocks/pll/CLKOUT}] -divide_by 4 [get_pins {clocks/divider/CLKOUT}]
# status_pipe is a two-flop synchronizer for diagnostic UART status.
set_false_path -from [get_clocks {ddr_ctrl}] -to [get_clocks {reference}]
