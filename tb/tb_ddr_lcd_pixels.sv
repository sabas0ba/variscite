module tb_ddr_lcd_pixels;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    wire frame, hs, vs, de, ready, out_hs, out_vs, out_de;
    wire [15:0] rgb;
    wire [31:0] underflows;
    logic valid=1, first, last;
    logic [127:0] data;
    int raster_frame=0, cycle=0, burst=0, source_frame=0;
    int hold_cycles=0;
    bit held_once=0, bad_tag_once=0;
    rv32ima_TangLcdTiming timing (
        .i_clk(clk),.i_rst(rst),.i_bars(1'b0),.i_bg(16'b0),.i_fg(16'b0),
        .i_x0(10'b0),.i_y0(9'b0),.i_x1(10'b0),.i_y1(9'b0),
        .o_frame(frame),.o_hs(hs),.o_vs(vs),.o_de(de),.o_rgb()
    );
    rv32ima_DdrLcdPixels pixels (
        .i_clk(clk),.i_rst(rst),.i_enable(1'b1),.i_frame(frame),.i_hs(hs),.i_vs(vs),.i_de(de),
        .i_valid(valid),.o_ready(ready),.i_data(data),.i_first(first),.i_last(last),
        .o_hs(out_hs),.o_vs(out_vs),.o_de(out_de),.o_rgb(rgb),.o_underflows(underflows)
    );
    function automatic logic [15:0] color(input int index);
        return 16'(index ^ (index>>9) ^ 32'h5ac3);
    endfunction
    always @(negedge clk) begin
        first=burst==0; last=burst==47999;
        for(int p=0;p<8;p++) data[p*16+:16]=color(burst*8+p);
        valid=hold_cycles==0;
        if(hold_cycles!=0) hold_cycles--;
        // Remove a required burst in raster 1, then resume. Raster 2 must
        // recover at pixel (0,0), without reusing any discarded frame data.
        if(raster_frame==1 && burst==100 && ready && !held_once) begin
            held_once=1; hold_cycles=20; valid=0;
        end
        // Mark a non-final burst as last in raster 3.
        if(raster_frame==3 && burst==200 && !bad_tag_once) last=1;
    end
    always @(posedge clk) if(!rst) begin
        bit expected_hs, expected_vs, expected_de;
        logic [15:0] expected_rgb;
        int x,y,index;
        x=cycle%1056; y=cycle/1056;
        expected_hs=!(x<128); expected_vs=!(y<3);
        expected_de=x>=216 && x<1016 && y>=24 && y<504;
        index=(y-24)*800+x-216;
        expected_rgb=0;
        if(expected_de) begin
            if((raster_frame!=1 || index<800) && (raster_frame!=3 || index<1600)) expected_rgb=color(index);
        end
        if(valid&&ready) begin
            if(raster_frame==3 && burst==200 && last) bad_tag_once=1;
            if(burst==47999) begin burst=0; source_frame++; end
            else burst++;
        end
        #1;
        if(out_hs!==expected_hs || out_vs!==expected_vs || out_de!==expected_de || rgb!==expected_rgb)
            $fatal(1,"LCD mismatch frame=%0d x=%0d y=%0d rgb=%h expected=%h underflows=%0d",raster_frame,x,y,rgb,expected_rgb,underflows);
        cycle++;
        if(cycle==1056*505) begin
            $display("LCD pixel frame %0d PASS, underflows=%0d",raster_frame,underflows);
            raster_frame++; cycle=0;
            if(raster_frame==5) begin
                if(underflows!=2 || !held_once || !bad_tag_once) $fatal(1,"fault/recovery coverage");
                $display("LCD pixel PASS: RGB565 order, sync/DE alignment, missing data/bad tag blanking, next-frame recovery");
                $finish;
            end
        end
    end
    initial begin repeat(3) @(negedge clk); rst=0; end
    initial begin #30000000; $fatal(1,"pixel test timeout"); end
endmodule
