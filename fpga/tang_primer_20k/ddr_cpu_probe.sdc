# Standalone word-probe clocks. Do not inherit the older diagnostic's blanket
# false path from ddr_ctrl to reference: it would hide response-mailbox routing.
create_clock -name reference -period 37.037037 [get_ports {i_clk}]
create_generated_clock -name ddr_fast -source [get_ports {i_clk}] -multiply_by 44 -divide_by 3 [get_pins {probe/clocks/pll/CLKOUT}]
create_generated_clock -name ddr_ctrl -source [get_pins {probe/clocks/pll/CLKOUT}] -divide_by 4 [get_pins {probe/clocks/divider/CLKOUT}]
# All ctrl->reference paths in this diagnostic terminate in CDC synchronizers,
# UART diagnostic mailboxes, or the word response mailbox. Response data is
# stable before the response toggle traverses two reference-clock registers;
# capture occurs on the following edge (>74 ns). Bound routing to 30 ns.
set_max_delay -from [get_clocks {ddr_ctrl}] -to [get_clocks {reference}] 30
# A same-edge phase hold check is not the CDC protocol: synchronizers tolerate
# an arbitrary first-stage capture, and mailbox data stays held until ack.
# Exempt hold only; the 30 ns setup/max-delay routing bound above remains active.
set_false_path -hold -from [get_clocks {ddr_ctrl}] -to [get_clocks {reference}]
# CPU request payload is held until response. The request toggle traverses two
# ctrl registers before the payload capture edge (>20 ns). Keep a 10 ns bound.
set_max_delay -from [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/address_mailbox*/Q}] -to [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/mem_address*/D}] 10
set_max_delay -from [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/write_mailbox*/Q}] -to [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/mem_write*/D}] 10
set_max_delay -from [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/strobe_mailbox*/Q}] -to [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/mem_strobe*/D}] 10
# Only first synchronizer stages are exempt from phase-related setup timing.
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/cpu_mode.cpu_probe/cpu_platform/word_port/u_cdc/request_sync_0_s0/D}]
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/cpu_mode.cpu_probe/done_sync_0_s0/D}]
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/cpu_mode.cpu_probe/found_sync_0_s0/D}]
set_false_path -from [get_clocks {ddr_ctrl}] -to [get_pins {probe/phy/lanes[0].lane/strobe/HOLD}]
set_false_path -from [get_clocks {ddr_ctrl}] -to [get_pins {probe/phy/lanes[1].lane/strobe/HOLD}]
