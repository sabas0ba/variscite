/// Basic synchronizer implementation using single-bit FF scheme
module __std_synchronizer_basic #(
    parameter int unsigned             WIDTH         = 8 ,
    parameter bit          [WIDTH-1:0] INITIAL_VALUE = '0,
    parameter int unsigned             STAGES        = 2 
) (
    input  var logic             i_clk,
    input  var logic             i_rst,
    input  var logic [WIDTH-1:0] i_d  ,
    output var logic [WIDTH-1:0] o_d  
);
    for (genvar i = 0; i < WIDTH; i++) begin :g
        logic [STAGES-1:0] rg;

        always_comb begin
            o_d[i] = rg[($size(rg, 1) - 1)];
        end

        always_ff @ (posedge i_clk) begin
            if (i_rst) begin
                rg <= {STAGES{INITIAL_VALUE[i]}};
            end else begin
                rg <= STAGES'({rg, i_d[i]});
            end
        end

    end
endmodule

//# sourceMappingURL=synchronizer_basic.sv.map
