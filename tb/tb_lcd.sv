module tb_lcd;
    reg clk = 0;
    reg rst = 1;
    wire hs, vs, de;
    wire [15:0] rgb;
    reg [15:0] bars [0:7];
    integer active;
    integer frames_checked=0;
    reg [9:0] x0=40, x1=160;
    reg [8:0] y0=180, y1=300;
    wire frame_start;
    reg [15:0] expected_rgb;
    reg bars_enabled = 1;
    rv32ima_TangLcdTiming dut (
        .i_clk(clk), .i_rst(rst), .o_hs(hs), .o_vs(vs), .o_de(de), .o_rgb(rgb)
        , .i_bars(bars_enabled), .i_bg(16'h0010), .i_fg(16'hffe0),
        .i_x0(x0), .i_y0(y0), .i_x1(x1), .i_y1(y1), .o_frame(frame_start)
    );
    always #5 clk = ~clk;
    initial begin #100000000; $fatal(1,"LCD watchdog"); end
    initial begin
        bars[0]=16'hffff; bars[1]=16'hffe0; bars[2]=16'h07ff; bars[3]=16'h07e0;
        bars[4]=16'hf81f; bars[5]=16'hf800; bars[6]=16'h001f; bars[7]=16'h0000;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;
        for (integer frame=0; frame<12; frame=frame+1) begin
            bars_enabled = frame < 2 || frame == 11;
            case(frame)
                3: begin x0=0; y0=0; x1=1; y1=1; end // first active pixel
                4: begin x0=799; y0=479; x1=800; y1=480; end // last active pixel
                5: begin x0=0; y0=0; x1=800; y1=480; end // full screen
                6: begin x0=799; y0=479; x1=1023; y1=511; end // clipped
                7: begin x0=800; y0=480; end // outside the screen
                8: begin x0=40; x1=40; y0=180; y1=300; end // zero width
                9: begin x0=160; x1=40; end // reversed horizontal bounds
                10: begin x0=40; x1=160; y0=300; y1=180; end // reversed vertical bounds
                11: begin
                    repeat(1056*100+400) @(negedge clk);
                    rst=1;
                    repeat(2) @(negedge clk);
                    #1; if(!frame_start || hs || vs || de || rgb!=0) $fatal(1,"reset during active scan");
                    @(negedge clk); rst=0;
                end
                default: begin end
            endcase
            active = 0;
            for (integer y=0; y<505; y=y+1) begin
                for (integer x=0; x<1056; x=x+1) begin
                    #1;
                    if (hs !== (x>=128) || vs !== (y>=3)) $fatal(1, "sync at %0d,%0d",x,y);
                    if (frame_start !== (x==0 && y==0)) $fatal(1,"frame marker at %0d,%0d",x,y);
                    if (de !== (x>=216 && x<1016 && y>=24 && y<504)) $fatal(1,"DE at %0d,%0d",x,y);
                    if (de) begin
                        active = active + 1;
                        if (bars_enabled) begin
                            if (rgb !== bars[(x-216)/100]) $fatal(1,"bar at %0d,%0d",x,y);
                        end else begin
                            expected_rgb=(x-216>=int'(x0) && x-216<int'(x1) && y-24>=int'(y0) && y-24<int'(y1)) ? 16'hffe0 : 16'h0010;
                            if (rgb !== expected_rgb) $fatal(1,"rectangle frame=%0d at %0d,%0d",frame,x,y);
                        end
                    end else if (rgb !== 0) $fatal(1,"blanking RGB");
                    @(negedge clk);
                end
            end
            if (active != 800*480) $fatal(1,"active pixel count %0d",active);
            frames_checked=frames_checked+1;
        end
        $display("PASS: %0d complete LCD frames, sync, frame marker, clipping, empty rectangles and mid-frame reset",frames_checked);
        $finish;
    end
endmodule
