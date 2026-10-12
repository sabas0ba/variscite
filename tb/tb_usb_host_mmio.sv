`timescale 1ns/1ps
module tb_usb_host_mmio;
    logic cpu_clk=0, usb_clk=0, reset=1;
    always #19 cpu_clk=~cpu_clk;
    always #8 usb_clk=~usb_clk;
    logic sel=0;
    logic [7:0] address=0;
    logic [31:0] write_data=0, read_data;
    logic [3:0] strobe=0;
    logic dir=0, nxt=0, drive, stp;
    logic [7:0] data=0, tx;
    rv32ima_UsbHostMmio #(.TRACE(1)) dut (
        .i_cpu_clk(cpu_clk), .i_usb_clk(usb_clk), .i_reset(reset),
        .i_sel(sel), .i_addr(address), .i_wdata(write_data), .i_wstrb(strobe), .o_rdata(read_data),
        .i_dir(dir), .i_nxt(nxt), .i_data(data), .o_data(tx), .o_drive(drive), .o_stp(stp)
    );
    task automatic usb_tick;
        @(posedge usb_clk); #1; @(negedge usb_clk); #1;
    endtask
    task automatic write_reg(input logic[7:0] addr, input logic[31:0] value, input logic[3:0] mask=15);
        @(negedge cpu_clk); address=addr; write_data=value; strobe=mask; sel=1;
        @(negedge cpu_clk); sel=0; strobe=0;
    endtask
    task automatic read_reg(input logic[7:0] addr, output logic[31:0] value);
        @(negedge cpu_clk); address=addr; #1; value=read_data;
    endtask
    task automatic wait_command(input logic[7:0] expected);
        int count=0;
        while (!(drive && tx==expected)) begin
            usb_tick(); count++;
            if(count>65000) $fatal(1,"missing PHY command %x",expected);
        end
    endtask
    task automatic phy_read(input logic[5:0] addr, input logic[7:0] value);
        wait_command({2'b11,addr}); nxt=1; usb_tick();
        dir=1; nxt=0; data=0; usb_tick();
        data=value; usb_tick(); dir=0; usb_tick(); usb_tick();
    endtask
    task automatic phy_write(input logic[5:0] addr, input logic[7:0] value);
        wait_command({2'b10,addr}); nxt=1; usb_tick();
        if(tx!=value) $fatal(1,"PHY write value %x != %x",tx,value);
        usb_tick();
        if(!stp) $fatal(1,"PHY write stop");
        usb_tick(); nxt=0; usb_tick();
    endtask
    task automatic completion(input logic[3:0] result, input logic[7:0] value);
        logic[31:0] status;
        int count=0;
        do begin
            read_reg(8'h08,status); count++;
            if(count>1000) $fatal(1,"MMIO timeout status=%x",status);
        end while((status&3)!=2);
        if(status[7:4]!=result || status[23:16]!=value) $fatal(1,"MMIO status=%x",status);
    endtask
    initial begin
        logic[31:0] value;
        repeat(4) usb_tick(); reset=0; repeat(4) usb_tick();
        read_reg(0,value); if(value!=32'h55484231) $fatal(1,"identity");
        write_reg(8'h40,32'h12345678);
        write_reg(8'h40,32'h0000ab00,2);
        read_reg(8'h40,value); if(value!=32'h1234ab78) $fatal(1,"byte strobes");
        write_reg(8'h10,0); write_reg(8'h0c,32'h80000004);
        read_reg(8'h08,value); if(!value[0]) $fatal(1,"busy not set");
        write_reg(8'h40,0); // TX storage is immutable during a transaction.
        phy_read(0,8'h24); completion(1,8'h24);
        begin
            int samples;
            bit saw_phy_value;
            saw_phy_value=0;
            read_reg(8'h18,value); samples=int'(value);
            if(samples<2 || samples>16) $fatal(1,"PHY trace length %d",samples);
            for(int n=0;n<samples;n++) begin
                read_reg(8'(8'hc0+4*n),value);
                if(value[16] && value[7:0]==8'h24) saw_phy_value=1;
            end
            if(!saw_phy_value) $fatal(1,"PHY trace missing read response");
        end
        read_reg(8'h40,value); if(value!=32'h1234ab78) $fatal(1,"busy write modified TX");
        write_reg(8'h10,32'h0000a516); write_reg(8'h0c,32'h80000005);
        phy_write(6'h16,8'ha5); completion(1,8'h24);
        // Invalid speed must fail without programming an invalid PHY mode.
        write_reg(8'h0c,32'h80000000); completion(7,0);
        // A common reset cancels an outstanding mailbox in both clock domains.
        write_reg(8'h10,0); write_reg(8'h0c,32'h80000004);
        wait_command(8'hc0); reset=1; repeat(4) usb_tick(); reset=0;
        repeat(6) usb_tick();
        read_reg(8'h08,value); if(value!=0) $fatal(1,"reset status");
        write_reg(8'h10,1); write_reg(8'h0c,32'h80000004);
        phy_read(1,8'h04); completion(1,8'h04);
        // Autonomous SOF switches to FS, emits the token and runs with no CPU.
        write_reg(8'h04,1);
        phy_write(6'h04,8'h45);
        wait_command(8'h45); nxt=1; usb_tick();
        if(tx!=1) $fatal(1,"SOF frame low byte");
        usb_tick(); usb_tick();
        if(!stp) $fatal(1,"SOF stop");
        usb_tick(); nxt=0; dir=1; data=0; usb_tick(); usb_tick();
        data=1; usb_tick(); dir=0; repeat(20) usb_tick();
        read_reg(8'h14,value); if(value[10:0]!=1 || value[11]) $fatal(1,"SOF counter %x",value);
        completion(1,8'h04); // SOF must preserve the last CPU completion.
        $display("PASS: USB MMIO strobes, busy protection, CDC mailboxes, reset, autonomous SOF");
        $finish;
    end
    initial begin #5000000; $fatal(1,"test timeout"); end
endmodule
