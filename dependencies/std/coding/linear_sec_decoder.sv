/// Decodes a Hamming encoded single-error-correcting bitvector into its closest word
module __std_linear_sec_decoder #(
    /// Number of parity bits
    parameter int unsigned P = 4,
    /// Length of codeword
    parameter int unsigned K = (1 << P) - 1,
    /// Length of data
    parameter int unsigned N = K - P
) (
    input  var logic [K-1:0] i_codeword,
    output var logic [N-1:0] o_word    ,
    /// Set iff the input codeword had a detected and corrected single-bit error in it
    output var logic o_corrected

);
    // 1-indexed codeword
    logic [(K + 1)-1:0] codeword          ; always_comb codeword           = {i_codeword, 1'b0};
    logic [(K + 1)-1:0] codeword_corrected;

    logic [P-1:0] errors;

    // Generate word from corrected codeword
    for (genvar idx = 1; idx < (K + 2); idx++) begin :g_create_word
        if (!$onehot(idx)) begin :g_data_bit
            localparam int unsigned CEIL             = $clog2(idx);
            localparam int unsigned WORD_IDX         = idx - 1 - CEIL;
            always_comb o_word[WORD_IDX] = codeword_corrected[idx];
        end
    end

    // Check parities
    // for k in 1..K + 1 :g_check_parities {
    //     const ERROR_IDX: u32 = k - 1;
    //     if $onehot(k) :g_error_check_parities {
    //         var masked_bits    : logic<K + 1>;
    //         assign masked_bits[0]  = 1'b0;
    //         const ONE_IDX_SET_BIT: u32 = $clog2(k);
    //         for idx in 1..K + 1 :g_check_bits {
    //             if idx[ONE_IDX_SET_BIT] :g_take_parity {
    //                 assign masked_bits[idx] = codeword[idx];
    //             } else {
    //                 assign masked_bits[idx] = 1'b0;
    //             }
    //         }
    //         assign errors[ERROR_IDX] = ^masked_bits;
    //     } else {
    //         assign errors[ERROR_IDX] = 1'b0;
    //     }
    // }
    for (genvar pbit = 1; pbit < P + 1; pbit++) begin :g_check_parities
        localparam int unsigned               ONE_IDX_SET_BIT = pbit - 1;
        logic        [(K + 1)-1:0] masked_bits    ;
        always_comb masked_bits[0]  = 1'b0;
        for (genvar idx = 1; idx < K + 1; idx++) begin :g_check_bits
            if (idx[ONE_IDX_SET_BIT]) begin :g_take_parity
                always_comb masked_bits[idx] = codeword[idx];
            end else begin :g_take_parity
                always_comb masked_bits[idx] = 1'b0;
            end
        end
        always_comb errors[ONE_IDX_SET_BIT] = ^masked_bits;
    end
    // for idx in 1..(K + 1) :g_check_parities {
    //     if $onehot(idx) :g_is_onehot {
    //         const ONE_IDX_SET_BIT: u32      = $clog2(idx);
    //         var masked_bits    : logic<K>;
    //         for idx2 in 1..(P + 1) :gen_mask {
    //             if idx2[ONE_IDX_SET_BIT] :g_take_parity {
    //                 assign masked_bits[idx2 - 1] = codeword[idx2];
    //             } else {
    //                 assign masked_bits[idx2 - 1] = 1'b0;
    //             }
    //         }
    //         assign errors[ONE_IDX_SET_BIT] = ~^masked_bits;
    //     }
    // }

    // Correct as needed
    always_comb o_corrected = |errors;
    always_comb begin
        codeword_corrected         =  codeword;
        codeword_corrected[errors] ^= 1;
    end
endmodule

//# sourceMappingURL=linear_sec_decoder.sv.map
