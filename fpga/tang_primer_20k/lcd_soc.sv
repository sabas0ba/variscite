// Tang Primer 20K SoC at 27 MHz, LCD scanout at 33 MHz.
module TangLcdSoc (
    input wire i_clk, i_uart_rx,
    output wire o_uart_tx,
    output wire lcd_dclk, lcd_hs, lcd_vs, lcd_de,
    output wire [4:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [4:0] lcd_b
);
    wire pixel_clk, locked, por;
    rv32ima_PowerOnReset reset_gen (.i_clk(i_clk), .o_rst(por));
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
    wire lcd_reset = por || !locked;
    // Common asynchronous assertion, synchronous release in each domain.
    (* async_reg = "true" *) reg [1:0] cpu_ready = 0, pixel_ready = 0;
    always @(posedge i_clk or posedge lcd_reset)
        if (lcd_reset) cpu_ready <= 0;
        else cpu_ready <= {cpu_ready[0], 1'b1};
    always @(posedge pixel_clk or posedge lcd_reset)
        if (lcd_reset) pixel_ready <= 0;
        else pixel_ready <= {pixel_ready[0], 1'b1};
    assign lcd_dclk = pixel_clk;
    TangLcdSystem system (
        .i_clk(i_clk), .i_rst(por), .i_pixel_clk(pixel_clk),
        .i_pixel_rst(!pixel_ready[1]), .i_lcd_ready(cpu_ready[1]),
        .i_uart_rx(i_uart_rx), .o_uart_tx(o_uart_tx), .o_retire(),
        .lcd_hs(lcd_hs), .lcd_vs(lcd_vs), .lcd_de(lcd_de), .lcd_rgb({lcd_r,lcd_g,lcd_b})
    );
endmodule
