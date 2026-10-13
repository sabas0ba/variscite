`timescale 1ns/1ps
// Source-synchronous PHY: control and DATA settle at different tCO values.
module tb_usb_ulpi_input;
    logic clk=0, reset=1;
    always #8.333 clk=~clk;
    wire sample_clk;
    assign #7.291 sample_clk=clk;
    logic dir=0, nxt=0, sampled_dir, sampled_nxt;
    logic [7:0] data=0, sampled_data, tx, value;
    logic valid=0, ready, done, error, drive, stp;
    logic [1:0] kind=2;
    logic [5:0] address=0;
    rv32ima_UsbUlpiInput sampler (
        .i_clk(sample_clk), .i_dir(dir), .i_nxt(nxt), .i_data(data),
        .o_dir(sampled_dir), .o_nxt(sampled_nxt), .o_data(sampled_data)
    );
    rv32ima_UsbUlpiLink link (
        .i_clk(clk), .i_rst(reset), .i_dir(sampled_dir), .i_nxt(sampled_nxt),
        .i_data(sampled_data), .o_data(tx), .o_drive(drive), .o_stp(stp),
        .i_valid(valid), .o_ready(ready), .i_kind(kind), .i_address(address),
        .i_value(8'ha5), .i_pid(4'd0), .i_length(7'd0), .o_index(), .i_byte(8'd0),
        .o_done(done), .o_error(error), .o_value(value), .o_rx_valid(),
        .o_rx_byte(), .o_rx_active(), .o_rx_error(), .o_line(), .o_line_valid()
    );
    task automatic phy_cycle(input bit d, input bit n, input logic [7:0] b);
        @(posedge clk);
        #1.5; dir=d; nxt=n;
        #2; data=b; // Data tCO=3.5 ns, control tCO=1.5 ns.
        @(posedge sample_clk); #0.1;
        if(sampled_dir!=d || sampled_nxt!=n || sampled_data!=b)
            $fatal(1,"incoherent PHY input snapshot");
    endtask
    task automatic start(input logic[1:0] op, input logic[5:0] addr);
        while(!ready) begin @(negedge clk); #0.1; end
        kind=op; address=addr; valid=1;
        @(posedge clk); #0.1; valid=0;
    endtask
    initial begin
        repeat(3) @(negedge clk);
        #0.1; reset=0;
        repeat(2) @(negedge clk);
        #0.1;
        for(int n=0;n<4;n++) begin
            logic[7:0] expected;
            expected=8'(8'h24+n);
            start(2,6'(n));
            phy_cycle(0,1,8'hff);
            if(tx!={2'b11,6'(n)}) $fatal(1,"read command");
            phy_cycle(1,0,8'hc0); // turnaround deliberately resembles command
            if(done) $fatal(1,"accepted turnaround");
            phy_cycle(1,0,expected);
            if(done) $fatal(1,"completed before valid data rising edge");
            phy_cycle(0,0,0);
            if(!done || error || value!=expected) $fatal(1,"read value %x",value);
            phy_cycle(0,0,0);
            phy_cycle(0,0,0);
        end
        start(1,6'h16);
        phy_cycle(0,1,0);
        phy_cycle(0,0,0);
        if(tx!=8'ha5 || stp) $fatal(1,"write data/stall");
        phy_cycle(0,1,0);
        phy_cycle(0,0,0);
        if(!stp) $fatal(1,"write STP");
        phy_cycle(0,0,0);
        if(!done || error) $fatal(1,"write completion");
        $display("PASS: ULPI phase-shifted input, unequal PHY tCO, register read/write and turnaround");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
