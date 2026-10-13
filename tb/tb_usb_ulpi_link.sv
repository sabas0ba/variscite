`timescale 1ns/1ps
module tb_usb_ulpi_link;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;
    logic dir = 0, nxt = 0;
    logic [7:0] data = 0, tx_data;
    logic drive, stp, valid = 0, ready, done, error;
    logic [1:0] kind = 0;
    logic [5:0] address = 0;
    logic [7:0] value = 0, result;
    logic [3:0] pid = 0;
    logic [6:0] length = 0, index;
    logic rx_valid, rx_active, rx_error;
    logic [7:0] rx_byte;
    logic [1:0] line_state;
    rv32ima_UsbUlpiLink dut (
        .i_clk(clk), .i_rst(rst), .i_dir(dir), .i_nxt(nxt), .i_data(data),
        .o_data(tx_data), .o_drive(drive), .o_stp(stp),
        .i_valid(valid), .o_ready(ready), .i_kind(kind), .i_address(address),
        .i_value(value), .i_pid(pid), .i_length(length), .o_index(index),
        .i_byte(8'h80 + {1'b0,index}), .o_done(done), .o_error(error), .o_value(result),
        .o_rx_valid(rx_valid), .o_rx_byte(rx_byte), .o_rx_active(rx_active),
        .o_rx_error(rx_error), .o_line(line_state), .o_line_valid()
    );
    task automatic tick;
        @(posedge clk); #1; @(negedge clk); #1;
    endtask
    task automatic start(input logic [1:0] op, input logic [6:0] count);
        while (!ready) tick();
        kind = op; length = count; valid = 1; tick(); valid = 0;
    endtask
    initial begin
        bit timed_out;
        repeat (3) tick(); rst = 0; tick();
        // Register write with command and data backpressure.
        address = 6'h04; value = 8'h41; start(1, 0);
        repeat (3) begin
            if (!drive || tx_data != 8'h84 || stp) $fatal(1,"write command");
            tick();
        end
        nxt = 1; tick(); nxt = 0;
        repeat (3) begin
            if (tx_data != 8'h41 || stp) $fatal(1,"write backpressure");
            tick();
        end
        nxt = 1; tick();
        if (!stp || tx_data != 0) $fatal(1,"write stop");
        tick(); nxt = 0;
        if (!done || error) $fatal(1,"write completion");
        tick();
        // Register read must not interpret turnaround or register value as RX.
        address = 6'h00; start(2,0);
        if (tx_data != 8'hc0) $fatal(1,"read command");
        nxt = 1; tick(); nxt = 0; dir = 1; data = 8'hff; #1;
        if (drive) $fatal(1,"DIR must immediately disable output");
        tick();
        if (done || rx_valid) $fatal(1,"read turnaround");
        data = 8'h24; tick();
        if (!done || result != 8'h24 || error) $fatal(1,"read result");
        dir = 0; #1;
        if (drive) $fatal(1,"return turnaround");
        tick(); tick();
        // PHY can interrupt a command before accepting it.
        pid = 4'h9; start(0,2);
        dir = 1; data = 8'h01; tick(); tick(); dir = 0; tick(); tick();
        if (tx_data != 8'h49) $fatal(1,"command retry");
        nxt = 1; tick(); nxt = 0;
        repeat (3) begin
            if (tx_data != 8'h80 || index != 1) $fatal(1,"packet stall");
            tick();
        end
        nxt = 1; tick();
        if (tx_data != 8'h81 || index != 2) $fatal(1,"packet byte1");
        // NXT has accepted the last byte: STP describes that previous cycle.
        // Dropping NXT now must not suppress or prolong the registered pulse.
        tick(); nxt = 0; #1;
        if (!stp) $fatal(1,"packet stop");
        tick(); nxt = 0;
        if (!done || error || stp) $fatal(1,"packet done");
        tick();
        // Zero-byte handshake, PID is conveyed in the command.
        pid = 4'h2; start(0,0); nxt = 1; tick();
        if (!stp) $fatal(1,"handshake stop");
        tick(); nxt = 0; tick();
        // Receive starts on DIR/NXT; turnaround byte is never delivered.
        dir = 1; nxt = 1; data = 8'hff; #1;
        if (rx_valid || drive) $fatal(1,"RX turnaround");
        tick(); data = 8'hc3; tick();
        if (!rx_valid || !rx_active || rx_byte != 8'hc3) $fatal(1,"RX PID");
        tick(); nxt = 0; data = 8'h11; tick();
        if (!rx_active || rx_error || line_state != 1) $fatal(1,"RXCMD active");
        data = 8'h31; tick();
        if (!rx_error) $fatal(1,"RX error");
        data = 8'h01; tick();
        if (rx_active) $fatal(1,"RX end");
        dir = 0; tick(); tick();
        // No PHY response cannot lock the bus client forever.
        start(2,0);
        timed_out = 0;
        repeat (65540) begin
            tick();
            if (done) begin
                if (!error) $fatal(1,"timeout not reported");
                timed_out = 1;
                break;
            end
        end
        if (!timed_out) $fatal(1,"missing timeout");
        $display("PASS: ULPI register/packet transfers, stalls, turnaround, RX error, timeout");
        $finish;
    end
    initial begin #2000000; $fatal(1,"test timeout"); end
endmodule
