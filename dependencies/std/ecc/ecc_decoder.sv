module __std_ecc_decoder #(
    parameter  int unsigned WIDTH       = 8                                         ,
    parameter  type         TYPE        = logic [WIDTH-1:0]                         ,
    localparam int unsigned DATA_WIDTH  = $bits(TYPE)                               ,
    localparam int unsigned CHECK_WIDTH = __std_ecc_pkg::get_check_width(DATA_WIDTH),
    localparam int unsigned CODE_WIDTH  = DATA_WIDTH + CHECK_WIDTH              
) (
    input  var logic                  i_enable   ,
    input  var logic [CODE_WIDTH-1:0] i_code     ,
    output var TYPE                   o_data     ,
    output var logic                  o_corrected,
    output var logic                  o_detected 
);
    logic [DATA_WIDTH-1:0]  data     ;
    logic [CHECK_WIDTH-1:0] syndrome ;
    logic [DATA_WIDTH-1:0]  error_pos;
    logic                   corrected;
    logic                   detected ;

    always_comb begin
        o_data      = data ^ error_pos;
        o_corrected = corrected;
        o_detected  = detected;
    end

    if (CHECK_WIDTH == 5) begin :g
        logic                                 [__std_hamming_11_5_pkg::CODE_WIDTH-1:0] code  ;
        __std_hamming_11_5_pkg::decode_result                                          result;

        always_comb begin
            code = __std_hamming_11_5_pkg::CODE_WIDTH'(i_code);
            if (i_enable) begin
                syndrome = __std_hamming_11_5_pkg::calc_syndrome(code);
                result   = __std_hamming_11_5_pkg::decode(syndrome, DATA_WIDTH);
            end else begin
                syndrome = '0;
                result   = '0;
            end

            data      = code[CHECK_WIDTH+:DATA_WIDTH];
            error_pos = result.error_pos[CHECK_WIDTH+:DATA_WIDTH];
            corrected = result.corrected;
            detected  = result.detected;
        end
    end else if (CHECK_WIDTH == 6) begin :g
        logic                                 [__std_hamming_26_6_pkg::CODE_WIDTH-1:0] code  ;
        __std_hamming_26_6_pkg::decode_result                                          result;

        always_comb begin
            code = __std_hamming_26_6_pkg::CODE_WIDTH'(i_code);
            if (i_enable) begin
                syndrome = __std_hamming_26_6_pkg::calc_syndrome(code);
                result   = __std_hamming_26_6_pkg::decode(syndrome, DATA_WIDTH);
            end else begin
                syndrome = '0;
                result   = '0;
            end

            data      = code[CHECK_WIDTH+:DATA_WIDTH];
            error_pos = result.error_pos[CHECK_WIDTH+:DATA_WIDTH];
            corrected = result.corrected;
            detected  = result.detected;
        end
    end else if (CHECK_WIDTH == 7) begin :g
        logic                                 [__std_hamming_57_7_pkg::CODE_WIDTH-1:0] code  ;
        __std_hamming_57_7_pkg::decode_result                                          result;

        always_comb begin
            code = __std_hamming_57_7_pkg::CODE_WIDTH'(i_code);
            if (i_enable) begin
                syndrome = __std_hamming_57_7_pkg::calc_syndrome(code);
                result   = __std_hamming_57_7_pkg::decode(syndrome, DATA_WIDTH);
            end else begin
                syndrome = '0;
                result   = '0;
            end

            data      = code[CHECK_WIDTH+:DATA_WIDTH];
            error_pos = result.error_pos[CHECK_WIDTH+:DATA_WIDTH];
            corrected = result.corrected;
            detected  = result.detected;
        end
    end else if (CHECK_WIDTH == 8) begin :g
        logic                                  [__std_hamming_120_8_pkg::CODE_WIDTH-1:0] code  ;
        __std_hamming_120_8_pkg::decode_result                                           result;

        always_comb begin
            code = __std_hamming_120_8_pkg::CODE_WIDTH'(i_code);
            if (i_enable) begin
                syndrome = __std_hamming_120_8_pkg::calc_syndrome(code);
                result   = __std_hamming_120_8_pkg::decode(syndrome, DATA_WIDTH);
            end else begin
                syndrome = '0;
                result   = '0;
            end

            data      = code[CHECK_WIDTH+:DATA_WIDTH];
            error_pos = result.error_pos[CHECK_WIDTH+:DATA_WIDTH];
            corrected = result.corrected;
            detected  = result.detected;
        end
    end else if (CHECK_WIDTH == 9) begin :g
        logic                                  [__std_hamming_247_9_pkg::CODE_WIDTH-1:0] code  ;
        __std_hamming_247_9_pkg::decode_result                                           result;

        always_comb begin
            code = __std_hamming_247_9_pkg::CODE_WIDTH'(i_code);
            if (i_enable) begin
                syndrome = __std_hamming_247_9_pkg::calc_syndrome(code);
                result   = __std_hamming_247_9_pkg::decode(syndrome, DATA_WIDTH);
            end else begin
                syndrome = '0;
                result   = '0;
            end

            data      = code[CHECK_WIDTH+:DATA_WIDTH];
            error_pos = result.error_pos[CHECK_WIDTH+:DATA_WIDTH];
            corrected = result.corrected;
            detected  = result.detected;
        end
    end else begin :g
        always_comb begin
            data      = '0;
            syndrome  = '0;
            error_pos = '0;
            corrected = 1'b0;
            detected  = 1'b0;
        end
    end
endmodule
//# sourceMappingURL=ecc_decoder.sv.map
