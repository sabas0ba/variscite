/// Edge detector
module __std_edge_detector #(
    /// Data width
    parameter int unsigned WIDTH = 1,
    /// Initial value of internal FF
    parameter bit [WIDTH-1:0] INITIAL_VALUE = '0
) (
    /// Clock
    input var logic i_clk,
    /// Reset
    input var logic i_rst,
    /// Clear
    input var logic i_clear,
    /// Data
    input var logic [WIDTH-1:0] i_data,
    /// Both edges
    output var logic [WIDTH-1:0] o_edge,
    /// Positive edge
    output var logic [WIDTH-1:0] o_posedge,
    /// Negative edge
    output var logic [WIDTH-1:0] o_negedge
);
    logic [WIDTH-1:0] data;

    always_comb o_edge    = (i_data) ^ (data) & (~i_clear);
    always_comb o_posedge = (i_data) & (~data) & (~i_clear);
    always_comb o_negedge = (~i_data) & (data) & (~i_clear);

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            data <= INITIAL_VALUE;
        end else if (i_clear) begin
            data <= INITIAL_VALUE;
        end else begin
            data <= i_data;
        end
    end
endmodule
//# sourceMappingURL=edge_detector.sv.map
