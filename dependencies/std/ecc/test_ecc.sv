module __std_test_ecc_wrapper #(
    parameter int unsigned DATA_WIDTH = 8                                        ,
    parameter int unsigned CODE_WIDTH = __std_ecc_pkg::get_code_width(DATA_WIDTH)
) (
    input  var logic [DATA_WIDTH-1:0] i_data     ,
    input  var logic [CODE_WIDTH-1:0] i_error    ,
    output var logic [DATA_WIDTH-1:0] o_data     ,
    output var logic                  o_corrected,
    output var logic                  o_detected 
);
    logic [CODE_WIDTH-1:0] code      ;
    logic [CODE_WIDTH-1:0] code_error;

    __std_ecc_encoder #(
        .WIDTH (DATA_WIDTH)
    ) u_encoder (
        .i_enable (1'b1  ),
        .i_data   (i_data),
        .o_code   (code  )
    );

    always_comb code_error = code ^ i_error;

    __std_ecc_decoder #(
        .WIDTH (DATA_WIDTH)
    ) u_decoder (
        .i_enable    (1'b1       ),
        .i_code      (code_error ),
        .o_data      (o_data     ),
        .o_corrected (o_corrected),
        .o_detected  (o_detected )
    );
endmodule





//# sourceMappingURL=test_ecc.sv.map
