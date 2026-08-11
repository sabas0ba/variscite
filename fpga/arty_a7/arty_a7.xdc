# Digilent Arty A7-35, pins taken from Digilent's Arty-A7-35-Master.xdc.
#
# The SoC runs from a divided clock (see fpga/arty_a7/top.veryl); the
# constraint here is on the 100 MHz board oscillator that feeds the divider.

set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { i_clk }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { i_clk }]

# USB-UART bridge. Digilent names these from the bridge's point of view:
# uart_rxd_out is driven by the FPGA, uart_txd_in is driven by the host.
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { o_uart_tx }]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { i_uart_rx }]

set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { o_led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { o_led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { o_led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { o_led[3] }]
