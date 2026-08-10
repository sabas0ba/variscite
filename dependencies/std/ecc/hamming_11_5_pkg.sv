package __std_hamming_11_5_pkg;
    // data width = 11 check width = 5
    // row[4]: 11111100100 | 10000
    // row[3]: 11010011110 | 01000
    // row[2]: 10101011101 | 00100
    // row[1]: 10110110011 | 00010
    // row[0]: 11001101011 | 00001

    localparam int unsigned DATA_WIDTH  = 11;
    localparam int unsigned CHECK_WIDTH = 5;
    localparam int unsigned CODE_WIDTH  = DATA_WIDTH + CHECK_WIDTH;

    // Coefficient matrix for check-bit generation.
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_0 = 11'h66b; // check[0]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_1 = 11'h5b3; // check[1]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_2 = 11'h55d; // check[2]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_3 = 11'h69e; // check[3]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_4 = 11'h7e4; // check[4]

    typedef struct packed {
        logic [CODE_WIDTH-1:0] error_pos; // error position (one-hot, [CHECK_WIDTH-1:0]=check, upper=data)
        logic                  corrected; // a single-bit error was located and corrected
        logic                  detected ; // an uncorrectable error was detected
    } decode_result;

    /// Compute the check bits (AND with the coefficient matrix, then XOR reduction).
    function automatic logic [CHECK_WIDTH-1:0] encode(
        input var logic [DATA_WIDTH-1:0] data
    ) ;
        logic [CHECK_WIDTH-1:0] check   ;
        check[0] = ^(ENCODE_MATRIX_ROW_0 & data);
        check[1] = ^(ENCODE_MATRIX_ROW_1 & data);
        check[2] = ^(ENCODE_MATRIX_ROW_2 & data);
        check[3] = ^(ENCODE_MATRIX_ROW_3 & data);
        check[4] = ^(ENCODE_MATRIX_ROW_4 & data);
        return check;
    endfunction

    /// Compute the syndrome (received check bits ^ recomputed check bits).
    function automatic logic [CHECK_WIDTH-1:0] calc_syndrome(
        input var logic [CODE_WIDTH-1:0] code
    ) ;
        logic [DATA_WIDTH-1:0]  data ;
        logic [CHECK_WIDTH-1:0] check;
        data  = code[CODE_WIDTH - 1-:DATA_WIDTH];
        check = code[0+:CHECK_WIDTH];
        return encode(data) ^ check;
    endfunction

    /// Determine the error position and flags (corrected/detected) from the syndrome.
    /// A data-bit correction is honored only while its index is below the active width.
    function automatic decode_result decode(
        input var logic        [CHECK_WIDTH-1:0] syndrome,
        input var int unsigned                   width   
    ) ;
        // Boolean-selector switch (SV: case (1'b1)); the syndrome values are mutually
        // exclusive, so the branches stay parallel while sharing the width gate.
        // A data branch that fails its width guard falls through to default -> detected.
        case (1'b1)
            syndrome == 5'h00               : return decode_result'{
                error_pos: 16'h0000                        ,
                corrected: 1'b0                            ,
                detected : 1'b0                            
            }; // no error
            syndrome == 5'h01               : return decode_result'{
                error_pos: 16'h0001                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[0]
            syndrome == 5'h02               : return decode_result'{
                error_pos: 16'h0002                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[1]
            syndrome == 5'h04               : return decode_result'{
                error_pos: 16'h0004                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[2]
            syndrome == 5'h08               : return decode_result'{
                error_pos: 16'h0008                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[3]
            syndrome == 5'h10               : return decode_result'{
                error_pos: 16'h0010                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[4]
            syndrome == 5'h07 && width >= 1 : return decode_result'{
                error_pos: 16'h0020                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[0]
            syndrome == 5'h0b && width >= 2 : return decode_result'{
                error_pos: 16'h0040                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[1]
            syndrome == 5'h1c && width >= 3 : return decode_result'{
                error_pos: 16'h0080                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[2]
            syndrome == 5'h0d && width >= 4 : return decode_result'{
                error_pos: 16'h0100                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[3]
            syndrome == 5'h0e && width >= 5 : return decode_result'{
                error_pos: 16'h0200                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[4]
            syndrome == 5'h13 && width >= 6 : return decode_result'{
                error_pos: 16'h0400                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[5]
            syndrome == 5'h15 && width >= 7 : return decode_result'{
                error_pos: 16'h0800                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[6]
            syndrome == 5'h1a && width >= 8 : return decode_result'{
                error_pos: 16'h1000                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[7]
            syndrome == 5'h16 && width >= 9 : return decode_result'{
                error_pos: 16'h2000                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[8]
            syndrome == 5'h19 && width >= 10: return decode_result'{
                error_pos: 16'h4000                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[9]
            syndrome == 5'h1f && width >= 11: return decode_result'{
                error_pos: 16'h8000                        ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[10]
            default                         : return decode_result'{
                error_pos: 16'h0000                        ,
                corrected: 1'b0                            ,
                detected : 1'b1                            
            }; // undefined syndrome / out-of-range (multiple-bit error)
        endcase
    endfunction
endpackage
//# sourceMappingURL=hamming_11_5_pkg.sv.map
