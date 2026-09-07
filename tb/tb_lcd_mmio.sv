module tb_lcd_mmio;
    reg cpu_clk=0, pixel_clk=0, rst=1, sel=0, frame=0;
    reg [31:0] addr=0, wdata=0;
    reg [3:0] wstrb=0;
    wire [31:0] rdata;
    wire [223:0] config_data;
    integer cpu_half=5, pixel_half=7;
    initial begin
        if ($value$plusargs("cpu_half=%d", cpu_half)) begin end
        if ($value$plusargs("pixel_half=%d", pixel_half)) begin end
        if (cpu_half < 1 || pixel_half < 1) $fatal(1,"invalid clock period");
    end
    integer cpu_count=0, pixel_count=0;
    always #1 begin
        cpu_count=cpu_count+1;
        pixel_count=pixel_count+1;
        if(cpu_count==cpu_half) begin cpu_count=0; cpu_clk=~cpu_clk; end
        if(pixel_count==pixel_half) begin pixel_count=0; pixel_clk=~pixel_clk; end
    end
    initial begin #1000000; $fatal(1,"MMIO watchdog"); end
    rv32ima_TangLcdMmio dut (
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
    reg [31:0] expected_stage [0:6];
    reg [31:0] random_state=32'h539c0def;
    reg [31:0] mask, data_value, merged;
    reg [223:0] snapshot;
    reg [3:0] strobes;
    function automatic [31:0] next_random(input [31:0] value);
        reg [31:0] v;
        v=value ^ (value << 13);
        v=v ^ (v >> 17);
        return v ^ (v << 5);
    endfunction
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
        @(negedge cpu_clk); rst=0;
        // All byte enables on all writable registers, against a software model.
        for(integer k=0;k<7;k=k+1) expected_stage[k]=(k==0) ? 1 : 0;
        for(integer pass=0;pass<16;pass=pass+1) begin
            for(integer k=0;k<7;k=k+1) begin
                random_state=next_random(random_state);
                data_value=random_state;
                strobes=4'(pass);
                merged=expected_stage[k];
                for(integer byte_index=0;byte_index<4;byte_index=byte_index+1)
                    if(strobes[byte_index]) merged[byte_index*8+:8]=data_value[byte_index*8+:8];
                case(k)
                    0: mask=1;
                    1,2: mask=32'hffff;
                    3,5: mask=1023;
                    default: mask=511;
                endcase
                expected_stage[k]=merged & mask;
                write_reg(32'h12000000+32'(k*4),data_value,strobes);
                read_check(32'h12000000+32'(k*4),expected_stage[k]);
            end
            // Deliberately overwrite staging after commit; all seven mailbox
            // words must still match the snapshot at the next frame.
            snapshot={expected_stage[6],expected_stage[5],expected_stage[4],
                      expected_stage[3],expected_stage[2],expected_stage[1],expected_stage[0]};
            write_reg(32'h1200001c,1,1);
            read_check(32'h1200001c,1);
            write_reg(32'h12000004,32'hdead,15);
            expected_stage[1]=32'hdead;
            repeat(8) @(negedge pixel_clk);
            next_frame();
            if(config_data !== snapshot) $fatal(1,"mailbox snapshot pass=%0d",pass);
            repeat(4) @(negedge cpu_clk);
            read_check(32'h1200001c,0);
        end
        // Every reserved word and the read-only ID must ignore writes.
        for(integer k=8;k<64;k=k+1) begin
            write_reg(32'h12000000+32'(k*4),32'hffffffff,15);
            read_check(32'h12000000+32'(k*4),(k==8) ? 32'h4c434431 : 0);
        end
        @(negedge cpu_clk); sel=0; addr=32'h12000020;
        #1; if(rdata !== 0) $fatal(1,"read while deselected");
        // Reset cancels an outstanding request and permits a new commit.
        write_reg(32'h1200001c,1,1);
        @(negedge cpu_clk); rst=1;
        repeat(5) @(negedge pixel_clk);
        repeat(5) @(negedge cpu_clk);
        rst=0;
        read_check(32'h1200001c,0);
        next_frame();
        if(config_data !== 224'd1) $fatal(1,"stale commit after reset");
        write_reg(32'h12000008,32'hf800,15);
        write_reg(32'h1200001c,1,1);
        repeat(8) @(negedge pixel_clk);
        next_frame();
        if(config_data[79:64] !== 16'hf800) $fatal(1,"commit after reset lost");
        $display("PASS: LCD MMIO 112 masked writes, 16 snapshots, reserved words, CDC and reset; clocks=%0d/%0d",cpu_half,pixel_half);
        $finish;
    end
endmodule
