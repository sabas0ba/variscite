package __std_hamming_247_9_pkg;
    // data width = 247 check width = 9
    // row[8]: 1111111111111111111111111111001000000111111111111111111111111111111111111111100100101010100101001010101010100000101010101000010001001010010100100001010000100100100111111111111111111111110110100000000000000000010000000000000000000000000000000000100 | 100000000
    // row[7]: 1111111111111111111100001000111111110111111111110101010101010000000010100000011011010101011010110101010101011111111111011111111111001010010100101001010100100100100111001000000000010000001001011111111011011011011001001100100000000000000000000000100 | 010000000
    // row[6]: 1111111111111100000011111110111111101110101000001010101010101111111010001000011011010101011010111111110110100100101010101010010100110101101011010111111111100100100000100111000000001000001001110000000100100100101110111111011111000000000000000000100 | 001000000
    // row[5]: 1111111101000011111011111101111111011001010111001010111101010100000101011010011011111101100101001010101001011011010101111010010100110101101011111101010100011011110000010000110010011100000000001010000100110010000100101000100100101010101010101010010 | 000100000
    // row[4]: 1111001010111011110111111011111110111001011100110101000010101011010101011101011100101010011010110110101001011011101010100101101100110101111100101010101110011011101000101000001001000100100100000101010010000100100010010100100100010101010101101010010 | 000010000
    // row[3]: 1100111011110111101111100111111101111101001001001101010010110101100110100111100011011010011111001001011011110100010101100101110010111110010011011010101101011110011000010100000100100010001100000100100101000110010001000010010010010101101010010101010 | 000001000
    // row[2]: 1011100111101111011111010111111011111010100010110010110011001010101101100110110110100110110100111001100101101110010110010111001011101001110011100110110011011101011100000010000110000001100010001001001000101000101001000001001010011010010110010110001 | 000000100
    // row[1]: 1101010111011110111110111111100111111010010011010011001100101100111010010101101101101001101101100110010110011101011001010110101011011011001110010111001011110011011010000000101000100001010001100000101010010001000010100001010001100110011001011001001 | 000000010
    // row[0]: 1010111100111101111101111111010111111100100100101100101101010011011001111011100100010111100011010101011110100011100101011001101111000110101101011100101011101011011001000001010001000010010010010010010001001001000100010010001001101001100101100101001 | 000000001

    localparam int unsigned DATA_WIDTH  = 247;
    localparam int unsigned CHECK_WIDTH = 9;
    localparam int unsigned CODE_WIDTH  = DATA_WIDTH + CHECK_WIDTH;

    // Coefficient matrix for check-bit generation.
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_0 = 247'h579efbfafe4965a9b3dc8bc6abd1cacde35ae575b20a21249224889134cb29; // check[0]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_1 = 247'h6aef7dfcfd26999674adb4db32ceb2b56d9cb979b40510a30548850a3332c9; // check[1]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_2 = 247'h5cf7bebf7d4596655b36d369ccb72cb974e7366eb810c0c4491452094d2cb1; // check[2]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_3 = 247'h677bdf3fbe926a5acd3c6d3e4b7a2b2e5f26d5af30a0911824a322124ad4aa; // check[3]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_4 = 247'h795defdfdcb9a855aaeb9535b52dd52d9af955cdd14122482a4244a48aab52; // check[4]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_5 = 247'h7fa1f7efecae57aa0ad37eca552dabd29ad7ea8de0864e0050990944955552; // check[5]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_6 = 247'h7ffe07f7f7505557f4436ab5fed255529ad6bff24138041380925dfbe00004; // check[6]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_7 = 247'h7ffff847fbffaaa805036ab5aaaffeffe5294a924e400812ff6db264000004; // check[7]
    localparam bit [DATA_WIDTH-1:0] ENCODE_MATRIX_ROW_8 = 247'h7ffffff903fffffffffc954a5550554225290a124fffffed00002000000004; // check[8]

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
        check[7] = ^(ENCODE_MATRIX_ROW_7 & data);
        check[8] = ^(ENCODE_MATRIX_ROW_8 & data);
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
            syndrome == 9'h000                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b0                                                                 ,
                detected : 1'b0                                                                 
            }; // no error
            syndrome == 9'h001                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000001,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[0]
            syndrome == 9'h002                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000002,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[1]
            syndrome == 9'h004                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000004,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[2]
            syndrome == 9'h008                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000008,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[3]
            syndrome == 9'h010                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000010,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[4]
            syndrome == 9'h020                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000020,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[5]
            syndrome == 9'h040                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000040,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[6]
            syndrome == 9'h080                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000080,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[7]
            syndrome == 9'h100                                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000100,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // check[8]
            syndrome == 9'h007 && width >= 1                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000200,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[0]
            syndrome == 9'h038 && width >= 2                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000400,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[1]
            syndrome == 9'h1c0 && width >= 3                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000800,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[2]
            syndrome == 9'h00b && width >= 4                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000001000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[3]
            syndrome == 9'h034 && width >= 5                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000002000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[4]
            syndrome == 9'h00d && width >= 6                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000004000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[5]
            syndrome == 9'h032 && width >= 7                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000008000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[6]
            syndrome == 9'h00e && width >= 8                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000010000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[7]
            syndrome == 9'h031 && width >= 9                                     : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000020000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[8]
            syndrome == 9'h013 && width >= 10                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000040000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[9]
            syndrome == 9'h02c && width >= 11                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000080000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[10]
            syndrome == 9'h015 && width >= 12                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000100000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[11]
            syndrome == 9'h02a && width >= 13                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000200000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[12]
            syndrome == 9'h016 && width >= 14                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000400000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[13]
            syndrome == 9'h029 && width >= 15                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000800000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[14]
            syndrome == 9'h019 && width >= 16                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000001000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[15]
            syndrome == 9'h026 && width >= 17                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000002000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[16]
            syndrome == 9'h01a && width >= 18                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000004000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[17]
            syndrome == 9'h025 && width >= 19                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000008000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[18]
            syndrome == 9'h01c && width >= 20                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000010000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[19]
            syndrome == 9'h023 && width >= 21                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000020000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[20]
            syndrome == 9'h043 && width >= 22                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000040000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[21]
            syndrome == 9'h04c && width >= 23                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000080000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[22]
            syndrome == 9'h070 && width >= 24                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000100000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[23]
            syndrome == 9'h045 && width >= 25                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000200000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[24]
            syndrome == 9'h04a && width >= 26                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000400000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[25]
            syndrome == 9'h0b0 && width >= 27                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000800000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[26]
            syndrome == 9'h046 && width >= 28                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000001000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[27]
            syndrome == 9'h049 && width >= 29                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000002000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[28]
            syndrome == 9'h0d0 && width >= 30                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000004000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[29]
            syndrome == 9'h0e0 && width >= 31                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000008000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[30]
            syndrome == 9'h051 && width >= 32                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000010000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[31]
            syndrome == 9'h062 && width >= 33                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000020000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[32]
            syndrome == 9'h08c && width >= 34                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000040000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[33]
            syndrome == 9'h052 && width >= 35                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000080000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[34]
            syndrome == 9'h061 && width >= 36                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000100000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[35]
            syndrome == 9'h0c4 && width >= 37                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000200000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[36]
            syndrome == 9'h188 && width >= 38                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000400000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[37]
            syndrome == 9'h054 && width >= 39                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000800000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[38]
            syndrome == 9'h083 && width >= 40                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000001000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[39]
            syndrome == 9'h0a8 && width >= 41                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000002000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[40]
            syndrome == 9'h058 && width >= 42                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000004000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[41]
            syndrome == 9'h085 && width >= 43                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000008000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[42]
            syndrome == 9'h0a2 && width >= 44                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000010000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[43]
            syndrome == 9'h064 && width >= 45                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000020000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[44]
            syndrome == 9'h089 && width >= 46                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000040000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[45]
            syndrome == 9'h092 && width >= 47                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000080000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[46]
            syndrome == 9'h068 && width >= 48                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000100000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[47]
            syndrome == 9'h086 && width >= 49                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000200000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[48]
            syndrome == 9'h091 && width >= 50                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000400000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[49]
            syndrome == 9'h08a && width >= 51                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000800000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[50]
            syndrome == 9'h094 && width >= 52                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000001000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[51]
            syndrome == 9'h0a1 && width >= 53                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000002000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[52]
            syndrome == 9'h098 && width >= 54                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000004000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[53]
            syndrome == 9'h0a4 && width >= 55                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000008000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[54]
            syndrome == 9'h0c1 && width >= 56                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000010000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[55]
            syndrome == 9'h142 && width >= 57                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000020000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[56]
            syndrome == 9'h0c2 && width >= 58                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000040000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[57]
            syndrome == 9'h105 && width >= 59                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000080000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[58]
            syndrome == 9'h118 && width >= 60                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000100000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[59]
            syndrome == 9'h0c8 && width >= 61                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000200000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[60]
            syndrome == 9'h103 && width >= 62                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000400000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[61]
            syndrome == 9'h114 && width >= 63                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000800000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[62]
            syndrome == 9'h106 && width >= 64                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000001000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[63]
            syndrome == 9'h109 && width >= 65                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000002000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[64]
            syndrome == 9'h130 && width >= 66                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000004000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[65]
            syndrome == 9'h160 && width >= 67                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000008000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[66]
            syndrome == 9'h1a0 && width >= 68                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000010000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[67]
            syndrome == 9'h10a && width >= 69                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000020000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[68]
            syndrome == 9'h111 && width >= 70                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000040000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[69]
            syndrome == 9'h124 && width >= 71                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000080000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[70]
            syndrome == 9'h10c && width >= 72                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000100000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[71]
            syndrome == 9'h112 && width >= 73                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000200000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[72]
            syndrome == 9'h121 && width >= 74                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000400000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[73]
            syndrome == 9'h122 && width >= 75                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000800000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[74]
            syndrome == 9'h141 && width >= 76                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000001000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[75]
            syndrome == 9'h144 && width >= 77                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000002000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[76]
            syndrome == 9'h148 && width >= 78                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000004000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[77]
            syndrome == 9'h190 && width >= 79                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000008000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[78]
            syndrome == 9'h128 && width >= 80                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000010000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[79]
            syndrome == 9'h150 && width >= 81                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000020000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[80]
            syndrome == 9'h181 && width >= 82                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000040000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[81]
            syndrome == 9'h182 && width >= 83                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000080000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[82]
            syndrome == 9'h184 && width >= 84                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000100000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[83]
            syndrome == 9'h01f && width >= 85                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000200000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[84]
            syndrome == 9'h02f && width >= 86                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000400000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[85]
            syndrome == 9'h1f0 && width >= 87                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000800000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[86]
            syndrome == 9'h037 && width >= 88                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000001000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[87]
            syndrome == 9'h03b && width >= 89                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000002000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[88]
            syndrome == 9'h1cc && width >= 90                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000004000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[89]
            syndrome == 9'h03d && width >= 91                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000008000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[90]
            syndrome == 9'h03e && width >= 92                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000010000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[91]
            syndrome == 9'h1c3 && width >= 93                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000020000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[92]
            syndrome == 9'h04f && width >= 94                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000040000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[93]
            syndrome == 9'h057 && width >= 95                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000080000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[94]
            syndrome == 9'h0f8 && width >= 96                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000100000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[95]
            syndrome == 9'h05b && width >= 97                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000200000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[96]
            syndrome == 9'h1e4 && width >= 98                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000400000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[97]
            syndrome == 9'h05d && width >= 99                                    : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000800000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[98]
            syndrome == 9'h1e2 && width >= 100                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000001000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[99]
            syndrome == 9'h05e && width >= 101                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000002000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[100]
            syndrome == 9'h067 && width >= 102                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000004000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[101]
            syndrome == 9'h0b9 && width >= 103                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000008000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[102]
            syndrome == 9'h06b && width >= 104                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000010000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[103]
            syndrome == 9'h1b4 && width >= 105                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000020000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[104]
            syndrome == 9'h06d && width >= 106                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000040000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[105]
            syndrome == 9'h06e && width >= 107                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000080000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[106]
            syndrome == 9'h193 && width >= 108                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000100000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[107]
            syndrome == 9'h073 && width >= 109                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000200000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[108]
            syndrome == 9'h19c && width >= 110                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000400000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[109]
            syndrome == 9'h075 && width >= 111                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000800000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[110]
            syndrome == 9'h076 && width >= 112                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000001000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[111]
            syndrome == 9'h18b && width >= 113                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000002000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[112]
            syndrome == 9'h079 && width >= 114                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000004000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[113]
            syndrome == 9'h18e && width >= 115                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000008000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[114]
            syndrome == 9'h07a && width >= 116                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000010000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[115]
            syndrome == 9'h07c && width >= 117                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000020000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[116]
            syndrome == 9'h187 && width >= 118                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000040000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[117]
            syndrome == 9'h08f && width >= 119                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000080000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[118]
            syndrome == 9'h0f1 && width >= 120                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000100000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[119]
            syndrome == 9'h097 && width >= 121                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000200000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[120]
            syndrome == 9'h1e8 && width >= 122                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000400000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[121]
            syndrome == 9'h09b && width >= 123                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000800000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[122]
            syndrome == 9'h09d && width >= 124                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000001000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[123]
            syndrome == 9'h0e6 && width >= 125                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000002000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[124]
            syndrome == 9'h09e && width >= 126                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000004000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[125]
            syndrome == 9'h1e1 && width >= 127                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000008000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[126]
            syndrome == 9'h0a7 && width >= 128                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000010000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[127]
            syndrome == 9'h178 && width >= 129                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000020000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[128]
            syndrome == 9'h0ab && width >= 130                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000040000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[129]
            syndrome == 9'h1d4 && width >= 131                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000080000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[130]
            syndrome == 9'h0ad && width >= 132                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000100000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[131]
            syndrome == 9'h1d2 && width >= 133                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000200000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[132]
            syndrome == 9'h0ae && width >= 134                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000400000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[133]
            syndrome == 9'h1d1 && width >= 135                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000000800000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[134]
            syndrome == 9'h0b3 && width >= 136                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000001000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[135]
            syndrome == 9'h0b5 && width >= 137                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000002000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[136]
            syndrome == 9'h0ce && width >= 138                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000004000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[137]
            syndrome == 9'h0b6 && width >= 139                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000008000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[138]
            syndrome == 9'h0ba && width >= 140                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000010000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[139]
            syndrome == 9'h14d && width >= 141                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000020000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[140]
            syndrome == 9'h0bc && width >= 142                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000040000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[141]
            syndrome == 9'h14b && width >= 143                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000080000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[142]
            syndrome == 9'h0c7 && width >= 144                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000100000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[143]
            syndrome == 9'h139 && width >= 145                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000200000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[144]
            syndrome == 9'h0cb && width >= 146                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000400000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[145]
            syndrome == 9'h174 && width >= 147                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000000800000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[146]
            syndrome == 9'h0cd && width >= 148                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000001000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[147]
            syndrome == 9'h172 && width >= 149                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000002000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[148]
            syndrome == 9'h0d3 && width >= 150                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000004000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[149]
            syndrome == 9'h16c && width >= 151                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000008000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[150]
            syndrome == 9'h0d5 && width >= 152                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000010000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[151]
            syndrome == 9'h0d6 && width >= 153                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000020000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[152]
            syndrome == 9'h12b && width >= 154                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000040000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[153]
            syndrome == 9'h0d9 && width >= 155                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000080000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[154]
            syndrome == 9'h12e && width >= 156                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000100000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[155]
            syndrome == 9'h0da && width >= 157                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000200000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[156]
            syndrome == 9'h0dc && width >= 158                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000400000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[157]
            syndrome == 9'h127 && width >= 159                                   : return decode_result'{
                error_pos: 256'h0000000000000000000000800000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[158]
            syndrome == 9'h0e3 && width >= 160                                   : return decode_result'{
                error_pos: 256'h0000000000000000000001000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[159]
            syndrome == 9'h11d && width >= 161                                   : return decode_result'{
                error_pos: 256'h0000000000000000000002000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[160]
            syndrome == 9'h0e5 && width >= 162                                   : return decode_result'{
                error_pos: 256'h0000000000000000000004000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[161]
            syndrome == 9'h13a && width >= 163                                   : return decode_result'{
                error_pos: 256'h0000000000000000000008000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[162]
            syndrome == 9'h0e9 && width >= 164                                   : return decode_result'{
                error_pos: 256'h0000000000000000000010000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[163]
            syndrome == 9'h136 && width >= 165                                   : return decode_result'{
                error_pos: 256'h0000000000000000000020000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[164]
            syndrome == 9'h0ea && width >= 166                                   : return decode_result'{
                error_pos: 256'h0000000000000000000040000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[165]
            syndrome == 9'h0ec && width >= 167                                   : return decode_result'{
                error_pos: 256'h0000000000000000000080000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[166]
            syndrome == 9'h117 && width >= 168                                   : return decode_result'{
                error_pos: 256'h0000000000000000000100000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[167]
            syndrome == 9'h0f2 && width >= 169                                   : return decode_result'{
                error_pos: 256'h0000000000000000000200000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[168]
            syndrome == 9'h0f4 && width >= 170                                   : return decode_result'{
                error_pos: 256'h0000000000000000000400000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[169]
            syndrome == 9'h10f && width >= 171                                   : return decode_result'{
                error_pos: 256'h0000000000000000000800000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[170]
            syndrome == 9'h11b && width >= 172                                   : return decode_result'{
                error_pos: 256'h0000000000000000001000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[171]
            syndrome == 9'h12d && width >= 173                                   : return decode_result'{
                error_pos: 256'h0000000000000000002000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[172]
            syndrome == 9'h11e && width >= 174                                   : return decode_result'{
                error_pos: 256'h0000000000000000004000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[173]
            syndrome == 9'h171 && width >= 175                                   : return decode_result'{
                error_pos: 256'h0000000000000000008000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[174]
            syndrome == 9'h133 && width >= 176                                   : return decode_result'{
                error_pos: 256'h0000000000000000010000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[175]
            syndrome == 9'h18d && width >= 177                                   : return decode_result'{
                error_pos: 256'h0000000000000000020000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[176]
            syndrome == 9'h135 && width >= 178                                   : return decode_result'{
                error_pos: 256'h0000000000000000040000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[177]
            syndrome == 9'h1ca && width >= 179                                   : return decode_result'{
                error_pos: 256'h0000000000000000080000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[178]
            syndrome == 9'h13c && width >= 180                                   : return decode_result'{
                error_pos: 256'h0000000000000000100000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[179]
            syndrome == 9'h147 && width >= 181                                   : return decode_result'{
                error_pos: 256'h0000000000000000200000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[180]
            syndrome == 9'h153 && width >= 182                                   : return decode_result'{
                error_pos: 256'h0000000000000000400000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[181]
            syndrome == 9'h14e && width >= 183                                   : return decode_result'{
                error_pos: 256'h0000000000000000800000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[182]
            syndrome == 9'h159 && width >= 184                                   : return decode_result'{
                error_pos: 256'h0000000000000001000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[183]
            syndrome == 9'h155 && width >= 185                                   : return decode_result'{
                error_pos: 256'h0000000000000002000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[184]
            syndrome == 9'h16a && width >= 186                                   : return decode_result'{
                error_pos: 256'h0000000000000004000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[185]
            syndrome == 9'h156 && width >= 187                                   : return decode_result'{
                error_pos: 256'h0000000000000008000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[186]
            syndrome == 9'h1a9 && width >= 188                                   : return decode_result'{
                error_pos: 256'h0000000000000010000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[187]
            syndrome == 9'h15a && width >= 189                                   : return decode_result'{
                error_pos: 256'h0000000000000020000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[188]
            syndrome == 9'h1a5 && width >= 190                                   : return decode_result'{
                error_pos: 256'h0000000000000040000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[189]
            syndrome == 9'h15c && width >= 191                                   : return decode_result'{
                error_pos: 256'h0000000000000080000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[190]
            syndrome == 9'h1a3 && width >= 192                                   : return decode_result'{
                error_pos: 256'h0000000000000100000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[191]
            syndrome == 9'h163 && width >= 193                                   : return decode_result'{
                error_pos: 256'h0000000000000200000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[192]
            syndrome == 9'h1ac && width >= 194                                   : return decode_result'{
                error_pos: 256'h0000000000000400000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[193]
            syndrome == 9'h165 && width >= 195                                   : return decode_result'{
                error_pos: 256'h0000000000000800000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[194]
            syndrome == 9'h19a && width >= 196                                   : return decode_result'{
                error_pos: 256'h0000000000001000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[195]
            syndrome == 9'h166 && width >= 197                                   : return decode_result'{
                error_pos: 256'h0000000000002000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[196]
            syndrome == 9'h199 && width >= 198                                   : return decode_result'{
                error_pos: 256'h0000000000004000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[197]
            syndrome == 9'h169 && width >= 199                                   : return decode_result'{
                error_pos: 256'h0000000000008000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[198]
            syndrome == 9'h196 && width >= 200                                   : return decode_result'{
                error_pos: 256'h0000000000010000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[199]
            syndrome == 9'h195 && width >= 201                                   : return decode_result'{
                error_pos: 256'h0000000000020000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[200]
            syndrome == 9'h1aa && width >= 202                                   : return decode_result'{
                error_pos: 256'h0000000000040000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[201]
            syndrome == 9'h1a6 && width >= 203                                   : return decode_result'{
                error_pos: 256'h0000000000080000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[202]
            syndrome == 9'h1b1 && width >= 204                                   : return decode_result'{
                error_pos: 256'h0000000000100000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[203]
            syndrome == 9'h1d8 && width >= 205                                   : return decode_result'{
                error_pos: 256'h0000000000200000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[204]
            syndrome == 9'h1b2 && width >= 206                                   : return decode_result'{
                error_pos: 256'h0000000000400000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[205]
            syndrome == 9'h1c5 && width >= 207                                   : return decode_result'{
                error_pos: 256'h0000000000800000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[206]
            syndrome == 9'h1b8 && width >= 208                                   : return decode_result'{
                error_pos: 256'h0000000001000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[207]
            syndrome == 9'h1c6 && width >= 209                                   : return decode_result'{
                error_pos: 256'h0000000002000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[208]
            syndrome == 9'h1c9 && width >= 210                                   : return decode_result'{
                error_pos: 256'h0000000004000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[209]
            syndrome == 9'h07f && width >= 211                                   : return decode_result'{
                error_pos: 256'h0000000008000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[210]
            syndrome == 9'h0bf && width >= 212                                   : return decode_result'{
                error_pos: 256'h0000000010000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[211]
            syndrome == 9'h0df && width >= 213                                   : return decode_result'{
                error_pos: 256'h0000000020000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[212]
            syndrome == 9'h0ef && width >= 214                                   : return decode_result'{
                error_pos: 256'h0000000040000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[213]
            syndrome == 9'h0f7 && width >= 215                                   : return decode_result'{
                error_pos: 256'h0000000080000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[214]
            syndrome == 9'h0fb && width >= 216                                   : return decode_result'{
                error_pos: 256'h0000000100000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[215]
            syndrome == 9'h1fc && width >= 217                                   : return decode_result'{
                error_pos: 256'h0000000200000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[216]
            syndrome == 9'h0fd && width >= 218                                   : return decode_result'{
                error_pos: 256'h0000000400000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[217]
            syndrome == 9'h0fe && width >= 219                                   : return decode_result'{
                error_pos: 256'h0000000800000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[218]
            syndrome == 9'h13f && width >= 220                                   : return decode_result'{
                error_pos: 256'h0000001000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[219]
            syndrome == 9'h15f && width >= 221                                   : return decode_result'{
                error_pos: 256'h0000002000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[220]
            syndrome == 9'h16f && width >= 222                                   : return decode_result'{
                error_pos: 256'h0000004000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[221]
            syndrome == 9'h1f3 && width >= 223                                   : return decode_result'{
                error_pos: 256'h0000008000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[222]
            syndrome == 9'h177 && width >= 224                                   : return decode_result'{
                error_pos: 256'h0000010000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[223]
            syndrome == 9'h17b && width >= 225                                   : return decode_result'{
                error_pos: 256'h0000020000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[224]
            syndrome == 9'h17d && width >= 226                                   : return decode_result'{
                error_pos: 256'h0000040000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[225]
            syndrome == 9'h17e && width >= 227                                   : return decode_result'{
                error_pos: 256'h0000080000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[226]
            syndrome == 9'h19f && width >= 228                                   : return decode_result'{
                error_pos: 256'h0000100000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[227]
            syndrome == 9'h1af && width >= 229                                   : return decode_result'{
                error_pos: 256'h0000200000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[228]
            syndrome == 9'h1b7 && width >= 230                                   : return decode_result'{
                error_pos: 256'h0000400000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[229]
            syndrome == 9'h1bb && width >= 231                                   : return decode_result'{
                error_pos: 256'h0000800000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[230]
            syndrome == 9'h1bd && width >= 232                                   : return decode_result'{
                error_pos: 256'h0001000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[231]
            syndrome == 9'h1be && width >= 233                                   : return decode_result'{
                error_pos: 256'h0002000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[232]
            syndrome == 9'h1cf && width >= 234                                   : return decode_result'{
                error_pos: 256'h0004000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[233]
            syndrome == 9'h1d7 && width >= 235                                   : return decode_result'{
                error_pos: 256'h0008000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[234]
            syndrome == 9'h1db && width >= 236                                   : return decode_result'{
                error_pos: 256'h0010000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[235]
            syndrome == 9'h1dd && width >= 237                                   : return decode_result'{
                error_pos: 256'h0020000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[236]
            syndrome == 9'h1ee && width >= 238                                   : return decode_result'{
                error_pos: 256'h0040000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[237]
            syndrome == 9'h1de && width >= 239                                   : return decode_result'{
                error_pos: 256'h0080000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[238]
            syndrome == 9'h1e7 && width >= 240                                   : return decode_result'{
                error_pos: 256'h0100000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[239]
            syndrome == 9'h1f9 && width >= 241                                   : return decode_result'{
                error_pos: 256'h0200000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[240]
            syndrome == 9'h1eb && width >= 242                                   : return decode_result'{
                error_pos: 256'h0400000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[241]
            syndrome == 9'h1ed && width >= 243                                   : return decode_result'{
                error_pos: 256'h0800000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[242]
            syndrome == 9'h1f6 && width >= 244                                   : return decode_result'{
                error_pos: 256'h1000000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[243]
            syndrome == 9'h1f5 && width >= 245                                   : return decode_result'{
                error_pos: 256'h2000000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[244]
            syndrome == 9'h1fa && width >= 246                                   : return decode_result'{
                error_pos: 256'h4000000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[245]
            syndrome == 9'h1ff && width >= 247                                   : return decode_result'{
                error_pos: 256'h8000000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b1                                                                 ,
                detected : 1'b0                                                                 
            }; // data[246]
            default                                                              : return decode_result'{
                error_pos: 256'h0000000000000000000000000000000000000000000000000000000000000000,
                corrected: 1'b0                                                                 ,
                detected : 1'b1                                                                 
            }; // undefined syndrome / out-of-range (multiple-bit error)
        endcase
    endfunction
endpackage
//# sourceMappingURL=hamming_247_9_pkg.sv.map
