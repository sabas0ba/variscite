package __std_hamming_26_6_pkg;
    // data width = 26 check width = 6
    // row[5]: 11111010101010101010101010 | 100000
    // row[4]: 11110101010101010110101010 | 010000
    // row[3]: 11101101010110101001010110 | 001000
    // row[2]: 11011101101001011001011001 | 000100
    // row[1]: 10111110011001100101100101 | 000010
    // row[0]: 01111110100110010110010101 | 000001

    localparam int unsigned DATA_WIDTH  = 26;
    localparam int unsigned CHECK_WIDTH = 6;
    localparam int unsigned CODE_WIDTH  = DATA_WIDTH + CHECK_WIDTH;

    // Coefficient matrix for check-bit generation.
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_0 = 26'h1fa6595; // check[0]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_1 = 26'h2f99965; // check[1]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_2 = 26'h3769659; // check[2]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_3 = 26'h3b56a56; // check[3]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_4 = 26'h3d555aa; // check[4]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_5 = 26'h3eaaaaa; // check[5]

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
        check[5] = ^(ENCODE_MATRIX_ROW_5 & data);
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
            syndrome == 6'h00               : return decode_result'{
                error_pos: 32'h00000000                    ,
                corrected: 1'b0                            ,
                detected : 1'b0                            
            }; // no error
            syndrome == 6'h01               : return decode_result'{
                error_pos: 32'h00000001                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[0]
            syndrome == 6'h02               : return decode_result'{
                error_pos: 32'h00000002                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[1]
            syndrome == 6'h04               : return decode_result'{
                error_pos: 32'h00000004                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[2]
            syndrome == 6'h08               : return decode_result'{
                error_pos: 32'h00000008                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[3]
            syndrome == 6'h10               : return decode_result'{
                error_pos: 32'h00000010                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[4]
            syndrome == 6'h20               : return decode_result'{
                error_pos: 32'h00000020                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[5]
            syndrome == 6'h07 && width >= 1 : return decode_result'{
                error_pos: 32'h00000040                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[0]
            syndrome == 6'h38 && width >= 2 : return decode_result'{
                error_pos: 32'h00000080                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[1]
            syndrome == 6'h0b && width >= 3 : return decode_result'{
                error_pos: 32'h00000100                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[2]
            syndrome == 6'h34 && width >= 4 : return decode_result'{
                error_pos: 32'h00000200                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[3]
            syndrome == 6'h0d && width >= 5 : return decode_result'{
                error_pos: 32'h00000400                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[4]
            syndrome == 6'h32 && width >= 6 : return decode_result'{
                error_pos: 32'h00000800                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[5]
            syndrome == 6'h0e && width >= 7 : return decode_result'{
                error_pos: 32'h00001000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[6]
            syndrome == 6'h31 && width >= 8 : return decode_result'{
                error_pos: 32'h00002000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[7]
            syndrome == 6'h13 && width >= 9 : return decode_result'{
                error_pos: 32'h00004000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[8]
            syndrome == 6'h2c && width >= 10: return decode_result'{
                error_pos: 32'h00008000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[9]
            syndrome == 6'h15 && width >= 11: return decode_result'{
                error_pos: 32'h00010000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[10]
            syndrome == 6'h2a && width >= 12: return decode_result'{
                error_pos: 32'h00020000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[11]
            syndrome == 6'h16 && width >= 13: return decode_result'{
                error_pos: 32'h00040000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[12]
            syndrome == 6'h29 && width >= 14: return decode_result'{
                error_pos: 32'h00080000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[13]
            syndrome == 6'h19 && width >= 15: return decode_result'{
                error_pos: 32'h00100000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[14]
            syndrome == 6'h26 && width >= 16: return decode_result'{
                error_pos: 32'h00200000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[15]
            syndrome == 6'h1a && width >= 17: return decode_result'{
                error_pos: 32'h00400000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[16]
            syndrome == 6'h25 && width >= 18: return decode_result'{
                error_pos: 32'h00800000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[17]
            syndrome == 6'h1c && width >= 19: return decode_result'{
                error_pos: 32'h01000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[18]
            syndrome == 6'h23 && width >= 20: return decode_result'{
                error_pos: 32'h02000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[19]
            syndrome == 6'h1f && width >= 21: return decode_result'{
                error_pos: 32'h04000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[20]
            syndrome == 6'h2f && width >= 22: return decode_result'{
                error_pos: 32'h08000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[21]
            syndrome == 6'h37 && width >= 23: return decode_result'{
                error_pos: 32'h10000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[22]
            syndrome == 6'h3b && width >= 24: return decode_result'{
                error_pos: 32'h20000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[23]
            syndrome == 6'h3d && width >= 25: return decode_result'{
                error_pos: 32'h40000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[24]
            syndrome == 6'h3e && width >= 26: return decode_result'{
                error_pos: 32'h80000000                    ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[25]
            default                         : return decode_result'{
                error_pos: 32'h00000000                    ,
                corrected: 1'b0                            ,
                detected : 1'b1                            
            }; // undefined syndrome / out-of-range (multiple-bit error)
        endcase
    endfunction
endpackage
//# sourceMappingURL=hamming_26_6_pkg.sv.map
