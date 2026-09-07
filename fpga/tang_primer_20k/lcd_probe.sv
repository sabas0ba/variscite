// Board-only wrapper: PLL parameters follow the Sipeed 800x480 timing profile.
// The timing generator is tested separately from the physical PLL primitive.
module TangLcdProbe (
    input wire i_clk,
    output wire lcd_dclk, lcd_hs, lcd_vs, lcd_de,
    output wire [4:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [4:0] lcd_b
);
    wire pixel_clk, locked;
    rPLL #(
        .FCLKIN("27"), .IDIV_SEL(8), .FBDIV_SEL(10), .ODIV_SEL(16),
        .CLKFB_SEL("internal"), .DEVICE("GW2A-18C")
    ) pll (
        .CLKIN(i_clk), .CLKOUT(pixel_clk), .LOCK(locked),
        .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
        .CLKOUTP(), .CLKOUTD(), .CLKOUTD3()
    );
    reg [1:0] ready = 2'b00;
    always @(posedge pixel_clk) begin
        if (!locked) ready <= 2'b00;
        else ready <= {ready[0], 1'b1};
    end
    // Clock phase follows the Sipeed 800x480 example.
    assign lcd_dclk = pixel_clk;
    rv32ima_TangLcdTiming timing (
        .i_clk(pixel_clk), .i_rst(!ready[1]),
        .o_hs(lcd_hs), .o_vs(lcd_vs), .o_de(lcd_de),
        .o_rgb({lcd_r, lcd_g, lcd_b})
    );
endmodule
