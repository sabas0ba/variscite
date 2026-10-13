# USB3317 CLKOUT: 60 MHz SDR. Data sheet DS00002366A table 4-3.
# PHY tCO=1.5..3.5 ns, setup=5 ns, hold=0 ns; allow 0.5 ns board skew.
create_clock -name usb_phy -period 16.667 [get_ports {usb_clk}]
create_generated_clock -name usb -source [get_ports {usb_clk}] -multiply_by 1 [get_pins {usb_clock/pll/CLKOUT}]
create_generated_clock -name usb_sample -source [get_ports {usb_clk}] -multiply_by 1 -phase 157.5 [get_pins {usb_clock/pll/CLKOUTP}]
set_input_delay -clock usb_phy -max 4.0 [get_ports {usb_dir usb_nxt usb_data[*]}]
set_input_delay -clock usb_phy -min 1.0 [get_ports {usb_dir usb_nxt usb_data[*]}]
set_output_delay -clock usb_phy -max 5.5 [get_ports {usb_stp usb_data[*]}]
set_output_delay -clock usb_phy -min -0.5 [get_ports {usb_stp usb_data[*]}]
# Bundled data stays stable for an entire mailbox handshake. Gray frame count
# changes once per millisecond. Bound all crossings to the faster clock period.
set_max_delay -from [get_clocks {reference}] -to [get_clocks {usb}] 15
set_max_delay -from [get_clocks {usb}] -to [get_clocks {reference}] 15
set_false_path -hold -from [get_clocks {reference}] -to [get_clocks {usb}]
set_false_path -hold -from [get_clocks {usb}] -to [get_clocks {reference}]
