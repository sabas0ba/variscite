`timescale 1ns/1ps
module tb_usb_host_transaction;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic valid=0, ready, done;
    logic [2:0] operation=0;
    logic [10:0] token=0;
    logic toggle=0, low_speed=0;
    logic [6:0] length=0, rx_length;
    logic [5:0] tx_index, rx_index;
    logic [7:0] tx_memory[64], rx_memory[64], rx_byte;
    logic rx_write, rx_toggle;
    logic [3:0] result;
    logic dir=0, nxt=0, drive, stp;
    logic [7:0] data=0, tx_data;
    logic [1:0] line_state;
    rv32ima_UsbHostTransaction dut (
        .i_clk(clk), .i_rst(rst), .i_valid(valid), .o_ready(ready),
        .i_operation(operation), .i_token(token), .i_toggle(toggle), .i_low_speed(low_speed),
        .i_length(length), .i_phy_address(6'h00), .i_phy_value(8'h00),
        .o_tx_index(tx_index), .i_tx_byte(tx_memory[tx_index]),
        .o_rx_write(rx_write), .o_rx_index(rx_index), .o_rx_byte(rx_byte),
        .o_done(done), .o_result(result), .o_length(rx_length), .o_toggle(rx_toggle),
        .o_phy_value(), .i_dir(dir), .i_nxt(nxt), .i_data(data),
        .o_data(tx_data), .o_drive(drive), .o_stp(stp), .o_line(line_state)
    );
    always @(posedge clk) if(rx_write) rx_memory[rx_index] <= rx_byte;
    task automatic tick;
        @(posedge clk); #1; @(negedge clk); #1;
    endtask
    function automatic [15:0] crc(input byte unsigned bytes[], input bit corrupt);
        logic [15:0] value;
        value=16'hffff;
        foreach(bytes[i]) for(int n=0;n<8;n++)
            value=(value>>1)^((value[0]^bytes[i][n])?16'ha001:16'h0000);
        return ~value ^ (corrupt?16'h0001:16'h0000);
    endfunction
    task automatic start(input logic[2:0] op, input logic[6:0] size);
        while(!ready) tick();
        operation=op; length=size; valid=1; tick(); valid=0;
    endtask
    task automatic tx_packet(input byte unsigned expected_pid, input byte unsigned expected[]);
        int deadline;
        deadline=0;
        while(!(drive && tx_data==expected_pid)) begin
            tick(); deadline++;
            if(deadline>400) $fatal(1,"no TX command %x, current %x", expected_pid,tx_data);
        end
        nxt=1; tick();
        foreach(expected[i]) begin
            if(stp || tx_data!=expected[i]) $fatal(1,"TX byte %0d: %x != %x",i,tx_data,expected[i]);
            // Exercise throttling during all transmitted packet types.
            nxt=0; repeat(2) tick(); nxt=1; tick();
        end
        if(!stp) $fatal(1,"missing packet STP");
        tick(); nxt=0;
        // PHY reports EOP and idle after flushing its transmit pipeline.
        dir=1; data=0; tick(); tick();
        data=low_speed?8'h02:8'h01; tick(); dir=0; tick(); tick();
    endtask
    task automatic rx_packet(input byte unsigned pid, input byte unsigned bytes[], input bit data_packet, input bit corrupt);
        logic[15:0] check;
        check=crc(bytes,corrupt);
        dir=1; nxt=1; data=8'hff; tick(); // turnaround
        data=pid; tick();
        foreach(bytes[i]) begin data=bytes[i]; tick(); end
        if(data_packet) begin data=check[7:0]; tick(); data=check[15:8]; tick(); end
        nxt=0; data=8'h01; tick(); dir=0; tick(); tick();
    endtask
    task automatic completion(input logic[3:0] expected);
        int deadline;
        deadline=0;
        while(!ready) begin
            tick(); deadline++;
            if(deadline>130000) $fatal(1,"missing transaction completion");
        end
        if(result!=expected) $fatal(1,"result %0d != %0d",result,expected);
        tick();
    endtask
    initial begin
        byte unsigned payload[], packet[];
        logic[15:0] check;
        for(int n=0;n<64;n++) tx_memory[n]=8'(n);
        repeat(3) tick(); rst=0; tick();
        // Known CRC5 vector: address 0 endpoint 0 -> token bytes 00 10.
        start(0,0); tx_packet(8'h49,'{8'h00,8'h10});
        rx_packet(8'hc3,'{8'h01,8'h02,8'h03},1,0);
        tx_packet(8'h42,'{}); completion(1);
        if(rx_length!=3 || rx_toggle || rx_memory[2]!=3) $fatal(1,"IN data");
        start(0,0); tx_packet(8'h49,'{8'h00,8'h10});
        rx_packet(8'h5a,'{},0,0); completion(2);
        start(0,0); tx_packet(8'h49,'{8'h00,8'h10});
        rx_packet(8'h1e,'{},0,0); completion(3);
        // Bad CRC must not be ACKed.
        start(0,0); tx_packet(8'h49,'{8'h00,8'h10});
        rx_packet(8'h4b,'{8'h55},1,1); completion(4);
        // DATA1 zero length is valid and must be ACKed.
        start(0,0); tx_packet(8'h49,'{8'h00,8'h10});
        rx_packet(8'h4b,'{},1,0); tx_packet(8'h42,'{}); completion(1);
        if(rx_length!=0 || !rx_toggle) $fatal(1,"zero length data1");
        // SETUP sends DATA0 and software-supplied setup bytes with CRC16.
        payload=new[8]; packet=new[10];
        foreach(payload[n]) begin payload[n]=8'(n); packet[n]=8'(n); end
        check=crc(payload,0); packet[8]=check[7:0]; packet[9]=check[15:8];
        start(2,8); tx_packet(8'h4d,'{8'h00,8'h10}); tx_packet(8'h43,packet);
        rx_packet(8'hd2,'{},0,0); completion(1);
        // OUT zero length includes two CRC bytes; low-speed timing is exercised.
        low_speed=1; toggle=1;
        start(1,0); tx_packet(8'h41,'{8'h00,8'h10}); tx_packet(8'h4b,'{8'h00,8'h00});
        rx_packet(8'hd2,'{},0,0); completion(1);
        low_speed=0;
        start(0,0); tx_packet(8'h49,'{8'h00,8'h10}); completion(5);
        start(1,65); completion(7);
        $display("PASS: USB IN/OUT/SETUP, token CRC, data CRC, ACK/NAK/STALL, zero length, timeout");
        $finish;
    end
    initial begin #5000000; $fatal(1,"test timeout"); end
endmodule
