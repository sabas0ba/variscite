/// Converts a Gray encoded bit vector to a binary encoded bit-vector
/// * Space Complexity: O(WIDTH log WIDTH)
/// * Time Complexity: O(log WIDTH)
module __std_gray_decoder #(
    /// Input and output bit vector width
    parameter int unsigned WIDTH = 1
) (
    /// Input Gray encoded Bit Vector
    input var logic [WIDTH-1:0] i_gray,
    /// Output binary encoded Bit Vector such that
    /// o_bin[k] = ^o_bin[WIDTH-1:k]
    output var logic [WIDTH-1:0] o_bin
);
    if (WIDTH == 1) begin :g_base
        always_comb o_bin = i_gray;
    end else begin :g_base
        localparam int unsigned BWIDTH = WIDTH / 2;
        localparam int unsigned TWIDTH = WIDTH - BWIDTH;

        // Top Bits
        logic [TWIDTH-1:0] top_in ; always_comb top_in  = i_gray[WIDTH - 1:BWIDTH];
        logic [TWIDTH-1:0] top_out;

        __std_gray_decoder #(
            .WIDTH (TWIDTH)
        ) u_top (
            .i_gray (top_in ),
            .o_bin  (top_out)
        );

        // Bot Bits
        logic [BWIDTH-1:0] bot_in ; always_comb bot_in  = i_gray[BWIDTH - 1:0];
        logic [BWIDTH-1:0] bot_out;
        // Have to xor all of the bottom bits with the xor-reduction of the top bits
        logic [BWIDTH-1:0] bot_red; always_comb bot_red = bot_out ^ {BWIDTH{top_out[0]}};

        __std_gray_decoder #(
            .WIDTH (BWIDTH)
        ) u_bot (
            .i_gray (bot_in ),
            .o_bin  (bot_out)
        );

        always_comb o_bin = {top_out, bot_red};
    end
endmodule
//# sourceMappingURL=gray_decoder.sv.map
