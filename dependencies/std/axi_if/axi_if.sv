///### AXI4 bus interface
///
///#### Modports:
///* master - AXI Master IP
///
///* slave - AXI slave IP
///
///* monitor - Debugging - All signals are declared as input
///
///* write_master - Reduced signal count for master IP that only writes to slave
///
///* read_master - Reduced signal count for master IP that only reads from slave
///
///* write_slave - Reduced signal count for slave IP that only receives writes from master
///
///* read_slave - Reduced signal count for slave IP that only replies to read requests from master
///
///#### Convenience functions:
///* awaddr_ack() = awready && awvalid
///
///* wdata_ack() = wready && wvalid
///
///* bresp_ack() = bready && bvalid
///
///* araddr_ack() = arready && arvalid
///
///* rdata_ack() = rready && rvalid
///
///#### Instantiation:
///```
///inst a: axi4_if::< axi4_pkg::< ADDR_W, DATA_W_BYTES, ID_W,
///                               AWUSER_W, WUSER_W, BUSER_W,
///                               ARUSER_W, RUSER_W > >;
///```
///#### Usage in module definition with modport:
///```
///module my_axi4_slave ( aclk: input clock_posedge,
///                       aresetn: input reset_sync_low,
///                       axi: modport axi4_if::<axi4_pkg::<32, 4, 8,
///                                                         8, 8, 8,
///                                                         8, 8>>::slave ) {
///
///}
///```




//# sourceMappingURL=axi_if.sv.map
