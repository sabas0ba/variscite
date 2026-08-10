/// Value counter using Gray Encoding
module __std_gray_counter #(
    /// Counter width
    parameter int unsigned WIDTH = 2,
    /// Max value of counter (in binary)
    parameter bit [WIDTH-1:0] MAX_COUNT = '1,
    /// Min value of counter (in binary)
    parameter bit [WIDTH-1:0] MIN_COUNT = '0,
    /// Initial value of counter (in binary)
    parameter bit [WIDTH-1:0] INITIAL_COUNT = MIN_COUNT,
    /// Whether counter is wrap around
    parameter bit WRAP_AROUND = 1,
    /// Counter type
    localparam type COUNT = logic [WIDTH-1:0]
) (
    /// Clock
    input var logic i_clk,
    /// Reset
    input var logic i_rst,
    /// Clear counter
    input var logic i_clear,
    /// Set counter to a value
    input var logic i_set,
    /// Value used by i_set
    input var COUNT i_set_value,
    /// Count up
    input var logic i_up,
    /// Count down
    input var logic i_down,
    /// Count value
    output var COUNT o_count,
    /// Count value for the next clock cycle
    output var COUNT o_count_next,
    /// Indicator for wrap around
    output var logic o_wrap_around
);

    COUNT bin_count     ;
    COUNT bin_count_next;

    __std_counter #(
        .WIDTH         (WIDTH        ),
        .MAX_COUNT     (MAX_COUNT    ),
        .MIN_COUNT     (MIN_COUNT    ),
        .INITIAL_COUNT (INITIAL_COUNT),
        .WRAP_AROUND   (WRAP_AROUND  )
    ) u_bin_counter (
        .i_clk         (i_clk         ),
        .i_rst         (i_rst         ),
        .i_clear       (i_clear       ),
        .i_set         (i_set         ),
        .i_set_value   (i_set_value   ),
        .i_up          (i_up          ),
        .i_down        (i_down        ),
        .o_count       (bin_count     ),
        .o_count_next  (bin_count_next),
        .o_wrap_around (o_wrap_around )
    );

    __std_gray_encoder #(
        .WIDTH (WIDTH)
    ) u_gray_cur (
        .i_bin  (bin_count),
        .o_gray (o_count  )
    );
    __std_gray_encoder #(
        .WIDTH (WIDTH)
    ) u_gray_next (
        .i_bin  (bin_count_next),
        .o_gray (o_count_next  )
    );

endmodule
//# sourceMappingURL=gray_counter.sv.map
