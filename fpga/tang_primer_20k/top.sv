// Sipeed Tang Primer 20K (Gowin GW2A-LV18PG256C8/I7).
//
// Only core-board pins are used - the 27 MHz crystal and the serial pair that
// reaches the USB bridge - so the port works whichever ext-board is fitted.
// Reset comes from an internal counter rather than a button, because the
// buttons live on the ext-board.
//
// This top is SystemVerilog rather than Veryl because it has to instantiate a
// vendor primitive. The core closes timing at about 19 MHz on this part (the M
// extension's single-cycle divide is the critical path), so it cannot run from
// the 27 MHz crystal directly, and dividing the clock in fabric is not an
// option here: with the SoC clocked from a flip-flop output, yosys's abc9
// mapping degrades badly - 23329 LUT4 against 17065, past what the part holds,
// and half an hour of run time against a minute and a half. Driving the clock
// from the PLL keeps it a real clock resource and the mapping stays sane.
//
// Build with `make fpga-tang`, program with `make fpga-tang-prog`.
module TangPrimer20k (
    input  wire i_clk,      // H11, 27 MHz
    input  wire i_uart_rx,  // T13
    output wire o_uart_tx   // M11
);

    // The clock rate, RAM size and baud divisor live in
    // fpga/tang_primer_20k/tang_soc.veryl, next to the rest of the Veryl.
    wire soc_clk;
    wire pll_locked;

    SysPll u_pll (
        .clock_in  (i_clk),
        .clock_out (soc_clk),
        .locked    (pll_locked)
    );

    // Held in reset until the PLL locks and then for a further 256 clocks. The
    // counter starts from the flip-flops' configuration state, which is zero,
    // so no external reset is needed to get it going.
    reg [7:0] por_count = 8'h00;
    reg       por_done  = 1'b0;

    always @(posedge soc_clk) begin
        if (!pll_locked) begin
            por_count <= 8'h00;
            por_done  <= 1'b0;
        end else if (!por_done) begin
            por_count <= por_count + 8'h01;
            if (&por_count) por_done <= 1'b1;
        end
    end

    wire rst = ~por_done;

    rv32ima_TangSoc u_soc (
        .i_clk     (soc_clk),
        .i_rst     (rst),
        .i_uart_rx (i_uart_rx),
        .o_uart_tx (o_uart_tx)
    );

endmodule
