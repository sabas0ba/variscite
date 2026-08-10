/// A binary decoder.
///
/// Converts a bit vector from a binary encoding to
/// a bit vector with a unary encoding.
module __std_binary_decoder #(
    /// Width of the input binary vector
    parameter int unsigned BIN_WIDTH = 8,
    /// Width of the output unary vector
    localparam int unsigned UNARY_WIDTH = 1 << BIN_WIDTH
) (
    /// Enable Signal.  Dynamic power is minimzed when not enabled.
    input var logic i_en,
    /// Binary encoded input.
    input var logic [BIN_WIDTH-1:0] i_bin,
    /// Unary encoded output.
    output var logic [UNARY_WIDTH-1:0] o_unary
);

    // Mask the binary encoded input with the enable signal to eliminate
    // dynamic power consumption while the decoder is not active.
    logic [BIN_WIDTH-1:0] masked_bin; always_comb masked_bin = i_bin & {BIN_WIDTH{i_en}};

    __std__bin_decoder #(
        .BIN_WIDTH (BIN_WIDTH)
    ) u_bin_decoder (
        .i_bin   (masked_bin),
        .o_unary (o_unary   )
    );

endmodule

module __std__bin_decoder #(
    parameter  int unsigned BIN_WIDTH   = 8             ,
    localparam int unsigned UNARY_WIDTH = 1 << BIN_WIDTH
) (
    /// Binary encoded
    input var logic [BIN_WIDTH-1:0] i_bin,
    /// Unary encoded output
    output var logic [UNARY_WIDTH-1:0] o_unary
);

    if (BIN_WIDTH == 1) begin :g_base_case
        always_comb o_unary = {i_bin, ~i_bin};
    end else begin :g_recurssive_case
        localparam int unsigned                       REC_BIN_WIDTH   = BIN_WIDTH - 1;
        localparam int unsigned                       REC_UNARY_WIDTH = 1 << REC_BIN_WIDTH;
        logic        [REC_BIN_WIDTH-1:0]   r_bin          ; always_comb r_bin           = i_bin[REC_BIN_WIDTH - 1:0];
        logic        [REC_UNARY_WIDTH-1:0] r_unary        ;

        __std__bin_decoder #(
            .BIN_WIDTH (REC_BIN_WIDTH)
        ) rec_bin_decoder (
            .i_bin   (r_bin  ),
            .o_unary (r_unary)
        );

        logic [REC_UNARY_WIDTH-1:0] mask_top; always_comb mask_top = ((i_bin[BIN_WIDTH - 1]) ? ( '1 ) : ( '0 ));
        logic [REC_UNARY_WIDTH-1:0] mask_bot; always_comb mask_bot = ~mask_top;

        always_comb o_unary = {r_unary, r_unary} & {mask_top, mask_bot};
    end
endmodule

//# sourceMappingURL=binary_decoder.sv.map
