module tb_lcd;
    reg clk = 0;
    reg rst = 1;
    wire hs, vs, de;
    wire [15:0] rgb;
    reg [15:0] bars [0:7];
    integer active;
    rv32ima_TangLcdTiming dut (
        .i_clk(clk), .i_rst(rst), .o_hs(hs), .o_vs(vs), .o_de(de), .o_rgb(rgb)
    );
    always #5 clk = ~clk;
    initial begin
        bars[0]=16'hffff; bars[1]=16'hffe0; bars[2]=16'h07ff; bars[3]=16'h07e0;
        bars[4]=16'hf81f; bars[5]=16'hf800; bars[6]=16'h001f; bars[7]=16'h0000;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;
        for (integer frame=0; frame<2; frame=frame+1) begin
            active = 0;
            for (integer y=0; y<505; y=y+1) begin
                for (integer x=0; x<1056; x=x+1) begin
                    #1;
                    if (hs !== (x>=128) || vs !== (y>=3)) $fatal(1, "sync at %0d,%0d",x,y);
                    if (de !== (x>=216 && x<1016 && y>=24 && y<504)) $fatal(1,"DE at %0d,%0d",x,y);
                    if (de) begin
                        active = active + 1;
                        if (rgb !== bars[(x-216)/100]) $fatal(1,"bar at %0d,%0d",x,y);
                    end else if (rgb !== 0) $fatal(1,"blanking RGB");
                    @(negedge clk);
                end
            end
            if (active != 800*480) $fatal(1,"active pixel count %0d",active);
        end
        $display("PASS: two 1056x505 frames, 800x480 active, sync widths, eight RGB565 bars");
        $finish;
    end
endmodule
