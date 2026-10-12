`timescale 1ns/1ps
module tb_sd_spi_mmio;
    logic clk=0, reset=1, sel=0;
    always #5 clk=~clk;
    logic [7:0] addr=0;
    logic [31:0] wdata=0, rdata;
    logic [3:0] strb=0;
    logic cs_n,sclk,mosi,miso=1;
    rv32ima_SdSpiMmio dut(.i_clk(clk),.i_reset(reset),.i_sel(sel),.i_addr(addr),
        .i_wdata(wdata),.i_wstrb(strb),.o_rdata(rdata),.o_cs_n(cs_n),.o_sclk(sclk),.o_mosi(mosi),.i_miso(miso));
    task automatic tick;
        @(posedge clk); #1; @(negedge clk); #1;
    endtask
    task automatic write_reg(input logic[7:0] a,input logic[31:0] d);
        addr=a;wdata=d;strb=1;sel=1;tick();sel=0;strb=0;
    endtask
    task automatic transfer(input logic[7:0] outgoing,input logic[7:0] incoming,input int half_period);
        int count,edge_index;
        logic old_clock;
        write_reg(12,{24'b0,outgoing});
        count=0;edge_index=0;old_clock=0;miso=incoming[7];
        while(edge_index<16) begin
            tick();count++;
            if(sclk!=old_clock) begin
                if(count!=half_period) $fatal(1,"SPI divider %0d != %0d",count,half_period);
                count=0;
                if(sclk && mosi!=outgoing[7-edge_index/2]) $fatal(1,"MOSI bit %0d",edge_index/2);
                if(!sclk && edge_index<15) miso=incoming[6-edge_index/2];
                old_clock=sclk;edge_index++;
            end
        end
        addr=8;#1;
        if(rdata[0] || rdata[15:8]!=incoming || sclk) $fatal(1,"SPI result %x",rdata);
    endtask
    initial begin
        repeat(3)tick();reset=0;tick();
        addr=0;#1;if(rdata!=32'h53445031 || !cs_n || sclk || !mosi) $fatal(1,"reset");
        write_reg(4,2);if(cs_n) $fatal(1,"select");
        transfer(8'ha5,8'h3c,64);
        write_reg(4,0);transfer(8'h69,8'h96,4);
        write_reg(4,1);if(!cs_n) $fatal(1,"deselect");
        transfer(8'hff,8'hff,4); // initialization clocks while deselected
        write_reg(12,0);repeat(3)tick();reset=1;tick();reset=0;tick();
        if(!cs_n || sclk) $fatal(1,"reset during transfer");
        $display("PASS: SD SPI mode 0, slow/fast clocks, bit order, receive, CS, reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
