# Reference-domain controls are held for eight 27 MHz cycles.
# Gowin gw2a/prim_sim.v DHCEN samples CE through four falling-edge registers.
# DQS samples HOLD through three falling-edge registers. Cut only their CDC inputs.
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/clocks/gate/CE}]
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/phy/lanes[0].lane/strobe/HOLD}]
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/phy/lanes[1].lane/strobe/HOLD}]
# ready_pipe is a two-register controller-domain synchronizer; its second stage
# remains timed. This synthesized first-stage name is checked in the build log.
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/ready_pipe_0_s0/D}]
# The registered PHY/divider reset releases only while DHCEN is stopped, eight
# reference clocks before restart. tb_ddr_phy_startup checks this invariant and
# the recovery interval. STA's continuously-running clock recovery model does
# not apply to fanout of this dedicated registered PHY reset source. No data
# or other startup control path originates at this flip-flop's Q.
set_false_path -from [get_pins {probe/phy_startup/o_phy_reset_s2/Q}]
set_false_path -from [get_clocks {reference}] -to [get_pins {probe/clocks/divider/RESETN}]
