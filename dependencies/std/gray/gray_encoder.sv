/// Converts a binary encoded bit vector to a Gray encoded bit-vector
/// * Space Complexity: O(WIDTH)
/// * Time Complexity: O(1)
module __std_gray_encoder #(
    /// Input and output bit vector width
    parameter int unsigned WIDTH = 32
) (
    /// Input Binary encoded Bit Vector
    input var logic [WIDTH-1:0] i_bin,
    /// Output Gray encoded Bit Vector
    output var logic [WIDTH-1:0] o_gray
);
    always_comb o_gray = i_bin ^ (i_bin >> 1);
endmodule

//# sourceMappingURL=gray_encoder.sv.map
