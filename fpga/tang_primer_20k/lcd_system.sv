// SoC and LCD integration, with explicit clocks for hardware and simulation.
module TangLcdSystem #(
    parameter integer CLK_HZ = 27000000,
    parameter integer UART_DIV = 15
) (
    input wire i_clk, i_rst,
    input wire i_pixel_clk, i_pixel_rst, i_lcd_ready,
    input wire i_uart_rx,
    output wire o_uart_tx, o_retire,
    output wire lcd_hs, lcd_vs, lcd_de,
    output wire [15:0] lcd_rgb
);
    wire ext_sel;
    wire [31:0] ext_addr, ext_wdata, ext_rdata;
    wire [3:0] ext_wstrb;
    wire frame_start;
    wire [223:0] config_data;
    rv32ima_FpgaSoc #(
        .CLK_HZ(CLK_HZ), .UART_DIV(UART_DIV), .RAM_WORDS(8192),
        .PMP_ENTRIES(4), .RAM_INIT("sim/fpga/firmware.hex")
    ) soc (
        .i_clk(i_clk), .i_rst(i_rst), .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx), .o_retire(o_retire),
        .o_ext_sel(ext_sel), .o_ext_addr(ext_addr),
        .o_ext_wstrb(ext_wstrb), .o_ext_wdata(ext_wdata), .i_ext_rdata(ext_rdata)
    );
    TangLcdMmio regs (
        .i_cpu_clk(i_clk), .i_cpu_rst(i_rst || !i_lcd_ready),
        .i_sel(ext_sel), .i_addr(ext_addr), .i_wstrb(ext_wstrb), .i_wdata(ext_wdata),
        .o_rdata(ext_rdata), .i_pixel_clk(i_pixel_clk), .i_pixel_rst(i_pixel_rst),
        .i_frame(frame_start), .o_config(config_data)
    );
    rv32ima_TangLcdTiming timing (
        .i_clk(i_pixel_clk), .i_rst(i_pixel_rst),
        .i_bars(config_data[0]), .i_bg(config_data[47:32]), .i_fg(config_data[79:64]),
        .i_x0(config_data[105:96]), .i_y0(config_data[136:128]),
        .i_x1(config_data[169:160]), .i_y1(config_data[200:192]),
        .o_frame(frame_start), .o_hs(lcd_hs), .o_vs(lcd_vs), .o_de(lcd_de), .o_rgb(lcd_rgb)
    );
endmodule
