create_clock -name reference -period 37.037037 [get_ports {i_clk}]
create_generated_clock -name ddr_fast -source [get_ports {i_clk}] -multiply_by 44 -divide_by 3 [get_pins {probe/clocks/pll/CLKOUT}]
create_generated_clock -name ddr_ctrl -source [get_pins {probe/clocks/pll/CLKOUT}] -divide_by 4 [get_pins {probe/clocks/divider/CLKOUT}]
# The UART status bits cross through two reference-clock registers.
set_false_path -from [get_clocks {ddr_ctrl}] -to [get_clocks {reference}]
# The DQS primitive resynchronizes HOLD on the fast falling edge internally.
set_false_path -from [get_clocks {ddr_ctrl}] -to [get_pins {probe/phy/lanes[0].lane/strobe/HOLD}]
set_false_path -from [get_clocks {ddr_ctrl}] -to [get_pins {probe/phy/lanes[1].lane/strobe/HOLD}]
