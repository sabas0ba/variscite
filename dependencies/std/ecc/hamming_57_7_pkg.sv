package __std_hamming_57_7_pkg;
    // data width = 57 check width = 7
    // row[6]: 111111111111111001000011111111111111100000000000000000000 | 1000000
    // row[5]: 111111110100010111111011101000000010010101010101010101010 | 0100000
    // row[4]: 111100101011110111110100010111000010001010101010110101010 | 0010000
    // row[3]: 110011101111001111101100011000101001001010110101001010110 | 0001000
    // row[2]: 101110011110101111011110000100010101001101001011001011001 | 0000100
    // row[1]: 110101011101111100111101000010011000110011001100101100101 | 0000010
    // row[0]: 101011110011111010111100100001100100110100110010110010101 | 0000001

    localparam int unsigned DATA_WIDTH  = 57;
    localparam int unsigned CHECK_WIDTH = 7;
    localparam int unsigned CODE_WIDTH  = DATA_WIDTH + CHECK_WIDTH;

    // Coefficient matrix for check-bit generation.
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_0 = 57'h15e7d790c9a6595; // check[0]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_1 = 57'h1abbe7a13199965; // check[1]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_2 = 57'h173d7bc22a69659; // check[2]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_3 = 57'h19de7d8c5256a56; // check[3]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_4 = 57'h1e57be8b84555aa; // check[4]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_5 = 57'h1fe8bf7404aaaaa; // check[5]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_6 = 57'h1fffc87fff00000; // check[6]

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
        check[6] = ^(ENCODE_MATRIX_ROW_6 & data);
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
            syndrome == 7'h00               : return decode_result'{
                error_pos: 64'h0000000000000000            ,
                corrected: 1'b0                            ,
                detected : 1'b0                            
            }; // no error
            syndrome == 7'h01               : return decode_result'{
                error_pos: 64'h0000000000000001            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[0]
            syndrome == 7'h02               : return decode_result'{
                error_pos: 64'h0000000000000002            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[1]
            syndrome == 7'h04               : return decode_result'{
                error_pos: 64'h0000000000000004            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[2]
            syndrome == 7'h08               : return decode_result'{
                error_pos: 64'h0000000000000008            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[3]
            syndrome == 7'h10               : return decode_result'{
                error_pos: 64'h0000000000000010            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[4]
            syndrome == 7'h20               : return decode_result'{
                error_pos: 64'h0000000000000020            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[5]
            syndrome == 7'h40               : return decode_result'{
                error_pos: 64'h0000000000000040            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // check[6]
            syndrome == 7'h07 && width >= 1 : return decode_result'{
                error_pos: 64'h0000000000000080            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[0]
            syndrome == 7'h38 && width >= 2 : return decode_result'{
                error_pos: 64'h0000000000000100            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[1]
            syndrome == 7'h0b && width >= 3 : return decode_result'{
                error_pos: 64'h0000000000000200            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[2]
            syndrome == 7'h34 && width >= 4 : return decode_result'{
                error_pos: 64'h0000000000000400            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[3]
            syndrome == 7'h0d && width >= 5 : return decode_result'{
                error_pos: 64'h0000000000000800            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[4]
            syndrome == 7'h32 && width >= 6 : return decode_result'{
                error_pos: 64'h0000000000001000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[5]
            syndrome == 7'h0e && width >= 7 : return decode_result'{
                error_pos: 64'h0000000000002000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[6]
            syndrome == 7'h31 && width >= 8 : return decode_result'{
                error_pos: 64'h0000000000004000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[7]
            syndrome == 7'h13 && width >= 9 : return decode_result'{
                error_pos: 64'h0000000000008000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[8]
            syndrome == 7'h2c && width >= 10: return decode_result'{
                error_pos: 64'h0000000000010000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[9]
            syndrome == 7'h15 && width >= 11: return decode_result'{
                error_pos: 64'h0000000000020000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[10]
            syndrome == 7'h2a && width >= 12: return decode_result'{
                error_pos: 64'h0000000000040000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[11]
            syndrome == 7'h16 && width >= 13: return decode_result'{
                error_pos: 64'h0000000000080000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[12]
            syndrome == 7'h29 && width >= 14: return decode_result'{
                error_pos: 64'h0000000000100000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[13]
            syndrome == 7'h19 && width >= 15: return decode_result'{
                error_pos: 64'h0000000000200000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[14]
            syndrome == 7'h26 && width >= 16: return decode_result'{
                error_pos: 64'h0000000000400000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[15]
            syndrome == 7'h1a && width >= 17: return decode_result'{
                error_pos: 64'h0000000000800000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[16]
            syndrome == 7'h25 && width >= 18: return decode_result'{
                error_pos: 64'h0000000001000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[17]
            syndrome == 7'h1c && width >= 19: return decode_result'{
                error_pos: 64'h0000000002000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[18]
            syndrome == 7'h23 && width >= 20: return decode_result'{
                error_pos: 64'h0000000004000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[19]
            syndrome == 7'h43 && width >= 21: return decode_result'{
                error_pos: 64'h0000000008000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[20]
            syndrome == 7'h4c && width >= 22: return decode_result'{
                error_pos: 64'h0000000010000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[21]
            syndrome == 7'h70 && width >= 23: return decode_result'{
                error_pos: 64'h0000000020000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[22]
            syndrome == 7'h45 && width >= 24: return decode_result'{
                error_pos: 64'h0000000040000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[23]
            syndrome == 7'h4a && width >= 25: return decode_result'{
                error_pos: 64'h0000000080000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[24]
            syndrome == 7'h46 && width >= 26: return decode_result'{
                error_pos: 64'h0000000100000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[25]
            syndrome == 7'h49 && width >= 27: return decode_result'{
                error_pos: 64'h0000000200000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[26]
            syndrome == 7'h51 && width >= 28: return decode_result'{
                error_pos: 64'h0000000400000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[27]
            syndrome == 7'h52 && width >= 29: return decode_result'{
                error_pos: 64'h0000000800000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[28]
            syndrome == 7'h54 && width >= 30: return decode_result'{
                error_pos: 64'h0000001000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[29]
            syndrome == 7'h68 && width >= 31: return decode_result'{
                error_pos: 64'h0000002000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[30]
            syndrome == 7'h58 && width >= 32: return decode_result'{
                error_pos: 64'h0000004000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[31]
            syndrome == 7'h61 && width >= 33: return decode_result'{
                error_pos: 64'h0000008000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[32]
            syndrome == 7'h62 && width >= 34: return decode_result'{
                error_pos: 64'h0000010000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[33]
            syndrome == 7'h64 && width >= 35: return decode_result'{
                error_pos: 64'h0000020000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[34]
            syndrome == 7'h1f && width >= 36: return decode_result'{
                error_pos: 64'h0000040000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[35]
            syndrome == 7'h2f && width >= 37: return decode_result'{
                error_pos: 64'h0000080000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[36]
            syndrome == 7'h37 && width >= 38: return decode_result'{
                error_pos: 64'h0000100000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[37]
            syndrome == 7'h3b && width >= 39: return decode_result'{
                error_pos: 64'h0000200000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[38]
            syndrome == 7'h7c && width >= 40: return decode_result'{
                error_pos: 64'h0000400000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[39]
            syndrome == 7'h3d && width >= 41: return decode_result'{
                error_pos: 64'h0000800000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[40]
            syndrome == 7'h3e && width >= 42: return decode_result'{
                error_pos: 64'h0001000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[41]
            syndrome == 7'h4f && width >= 43: return decode_result'{
                error_pos: 64'h0002000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[42]
            syndrome == 7'h73 && width >= 44: return decode_result'{
                error_pos: 64'h0004000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[43]
            syndrome == 7'h57 && width >= 45: return decode_result'{
                error_pos: 64'h0008000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[44]
            syndrome == 7'h5b && width >= 46: return decode_result'{
                error_pos: 64'h0010000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[45]
            syndrome == 7'h5d && width >= 47: return decode_result'{
                error_pos: 64'h0020000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[46]
            syndrome == 7'h6e && width >= 48: return decode_result'{
                error_pos: 64'h0040000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[47]
            syndrome == 7'h5e && width >= 49: return decode_result'{
                error_pos: 64'h0080000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[48]
            syndrome == 7'h67 && width >= 50: return decode_result'{
                error_pos: 64'h0100000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[49]
            syndrome == 7'h79 && width >= 51: return decode_result'{
                error_pos: 64'h0200000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[50]
            syndrome == 7'h6b && width >= 52: return decode_result'{
                error_pos: 64'h0400000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[51]
            syndrome == 7'h6d && width >= 53: return decode_result'{
                error_pos: 64'h0800000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[52]
            syndrome == 7'h76 && width >= 54: return decode_result'{
                error_pos: 64'h1000000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[53]
            syndrome == 7'h75 && width >= 55: return decode_result'{
                error_pos: 64'h2000000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[54]
            syndrome == 7'h7a && width >= 56: return decode_result'{
                error_pos: 64'h4000000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[55]
            syndrome == 7'h7f && width >= 57: return decode_result'{
                error_pos: 64'h8000000000000000            ,
                corrected: 1'b1                            ,
                detected : 1'b0                            
            }; // data[56]
            default                         : return decode_result'{
                error_pos: 64'h0000000000000000            ,
                corrected: 1'b0                            ,
                detected : 1'b1                            
            }; // undefined syndrome / out-of-range (multiple-bit error)
        endcase
    endfunction
endpackage
//# sourceMappingURL=hamming_57_7_pkg.sv.map
