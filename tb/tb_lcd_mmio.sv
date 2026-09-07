module tb_lcd_mmio;
    reg cpu_clk=0, pixel_clk=0, rst=1, sel=0, frame=0;
    reg [31:0] addr=0, wdata=0;
    reg [3:0] wstrb=0;
    wire [31:0] rdata;
    wire [223:0] config_data;
    always #5 cpu_clk=~cpu_clk;
    always #7 pixel_clk=~pixel_clk;
    TangLcdMmio dut (
        .i_cpu_clk(cpu_clk), .i_cpu_rst(rst), .i_sel(sel), .i_addr(addr),
        .i_wdata(wdata), .i_wstrb(wstrb), .o_rdata(rdata),
        .i_pixel_clk(pixel_clk), .i_pixel_rst(rst), .i_frame(frame), .o_config(config_data)
    );
    task automatic write_reg(input [31:0] a, input [31:0] d, input [3:0] s);
        @(negedge cpu_clk); sel=1; addr=a; wdata=d; wstrb=s;
        @(negedge cpu_clk); sel=0; wstrb=0;
    endtask
    task automatic read_check(input [31:0] a, input [31:0] expected);
        @(negedge cpu_clk); sel=1; addr=a; wstrb=0;
        #1; if (rdata !== expected) $fatal(1,"read %h: got %h expected %h",a,rdata,expected);
        @(negedge cpu_clk); sel=0;
    endtask
    task automatic next_frame;
        @(negedge pixel_clk); frame=1;
        @(negedge pixel_clk); frame=0;
    endtask
    initial begin
        repeat(4) @(negedge cpu_clk);
        rst=0;
        read_check(32'h12000020,32'h4c434431);
        read_check(32'h12000120,0);
        read_check(32'h120000fc,0);
        read_check(32'h1200001c,0);
        read_check(32'h12000000,1);
        write_reg(32'h12000008,32'h12345678,4'b1111);
        read_check(32'h12000008,32'h5678);
        write_reg(32'h12000009,32'hab00,4'b0010);
        read_check(32'h12000008,32'hab78);
        write_reg(32'h12000008,32'hffff0000,4'b1100);
        read_check(32'h12000008,32'hab78);
        write_reg(32'h1200000c,32'hffffffff,4'b1111);
        read_check(32'h1200000c,1023);
        write_reg(32'h12000010,32'hffffffff,4'b1111);
        read_check(32'h12000010,511);
        write_reg(32'h12000000,0,4'b0001);
        write_reg(32'h1200001c,1,4'b0010); // commit is in byte zero
        read_check(32'h1200001c,0);
        write_reg(32'h1200001c,1,4'b0001);
        read_check(32'h1200001c,1);
        write_reg(32'h12000008,32'h07e0,4'b0011);
        write_reg(32'h1200001c,1,4'b0001); // busy: must not replace mailbox
        repeat(8) @(negedge pixel_clk);
        if(config_data !== 224'd1) $fatal(1,"configuration changed inside frame");
        next_frame();
        if(config_data[79:64] !== 16'hab78 || config_data[0] !== 0)
            $fatal(1,"first commit torn or overwritten");
        repeat(4) @(negedge cpu_clk);
        read_check(32'h1200001c,0);
        write_reg(32'h1200001c,1,4'b0001);
        repeat(8) @(negedge pixel_clk);
        if(config_data[79:64] !== 16'hab78) $fatal(1,"second update before frame boundary");
        next_frame();
        if(config_data[79:64] !== 16'h07e0) $fatal(1,"second commit missing");
        write_reg(32'h12000108,32'hffff,4'b0011);
        read_check(32'h12000008,32'h07e0);
        @(negedge cpu_clk); rst=1;
        repeat(4) @(negedge pixel_clk);
        if(config_data !== 224'd1) $fatal(1,"reset did not restore bars");
        $display("PASS: LCD MMIO decode, byte enables, masks, CDC, frame commit, busy and reset");
        $finish;
    end
endmodule
