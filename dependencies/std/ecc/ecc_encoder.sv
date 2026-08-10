module __std_ecc_encoder #(
    parameter  int unsigned WIDTH       = 8                                         ,
    parameter  type         TYPE        = logic [WIDTH-1:0]                         ,
    localparam int unsigned DATA_WIDTH  = $bits(TYPE)                               ,
    localparam int unsigned CHECK_WIDTH = __std_ecc_pkg::get_check_width(DATA_WIDTH),
    localparam int unsigned CODE_WIDTH  = DATA_WIDTH + CHECK_WIDTH              
) (
    input  var logic                  i_enable,
    input  var TYPE                   i_data  ,
    output var logic [CODE_WIDTH-1:0] o_code  
);
    logic [CHECK_WIDTH-1:0] check;

    always_comb begin
        o_code = {i_data, check};
    end

    if (CHECK_WIDTH == 5) begin :g
        logic [__std_hamming_11_5_pkg::DATA_WIDTH-1:0] data;

        always_comb begin
            data = __std_hamming_11_5_pkg::DATA_WIDTH'(i_data);
            if (i_enable) begin
                check = CHECK_WIDTH'(__std_hamming_11_5_pkg::encode(data));
            end else begin
                check = '0;
            end
        end
    end else if (CHECK_WIDTH == 6) begin :g
        logic [__std_hamming_26_6_pkg::DATA_WIDTH-1:0] data;

        always_comb begin
            data = __std_hamming_26_6_pkg::DATA_WIDTH'(i_data);
            if (i_enable) begin
                check = CHECK_WIDTH'(__std_hamming_26_6_pkg::encode(data));
            end else begin
                check = '0;
            end
        end
    end else if (CHECK_WIDTH == 7) begin :g
        logic [__std_hamming_57_7_pkg::DATA_WIDTH-1:0] data;

        always_comb begin
            data = __std_hamming_57_7_pkg::DATA_WIDTH'(i_data);
            if (i_enable) begin
                check = CHECK_WIDTH'(__std_hamming_57_7_pkg::encode(data));
            end else begin
                check = '0;
            end
        end
    end else if (CHECK_WIDTH == 8) begin :g
        logic [__std_hamming_120_8_pkg::DATA_WIDTH-1:0] data;

        always_comb begin
            data = __std_hamming_120_8_pkg::DATA_WIDTH'(i_data);
            if (i_enable) begin
                check = CHECK_WIDTH'(__std_hamming_120_8_pkg::encode(data));
            end else begin
                check = '0;
            end
        end
    end else if (CHECK_WIDTH == 9) begin :g
        logic [__std_hamming_247_9_pkg::DATA_WIDTH-1:0] data;

        always_comb begin
            data = __std_hamming_247_9_pkg::DATA_WIDTH'(i_data);
            if (i_enable) begin
                check = CHECK_WIDTH'(__std_hamming_247_9_pkg::encode(data));
            end else begin
                check = '0;
            end
        end
    end else begin :g
        always_comb begin
            check = '0;
        end
    end
endmodule
//# sourceMappingURL=ecc_encoder.sv.map
