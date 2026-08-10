/// Enocdes a vector for single-error correction using a linear Hamming code.
module __std_linear_sec_encoder #(
    /// Number of parity bits
    parameter int unsigned P = 4,
    /// Length of codeword
    parameter int unsigned K = (1 << P) - 1,
    /// Length of data
    parameter int unsigned N = K - P
) (
    input  var logic [N-1:0] i_word    ,
    output var logic [K-1:0] o_codeword
);

    // Generate H Matrix
    logic [P-1:0][K-1:0] h;
    for (genvar p = 0; p < P; p++) begin :gen_vector
        for (genvar k = 0; k < K; k++) begin :gen_bit
            localparam int unsigned IDX     = k + 1;
            always_comb h[p][k] = IDX[p];
        end
    end

    // Move data from input word to its larger k-bit length vector
    logic [K-1:0] codeword_data_only;
    for (genvar k = 1; k < K + 1; k++) begin :gen_move_data
        localparam int unsigned CODEWORD_IDX = k - 1;
        if (!$onehot(k)) begin :gen_move_data_bit
            localparam int unsigned WORD_IDX                         = k - $clog2(k) - 1;
            always_comb codeword_data_only[CODEWORD_IDX] = i_word[WORD_IDX];
        end else begin :gen_move_data_bit
            always_comb codeword_data_only[CODEWORD_IDX] = 1'b0;
        end
    end

    // Compute parity bits
    logic [K-1:0] codeword_parity_only;
    for (genvar p = 0; p < P; p++) begin :gen_parities
        localparam int unsigned CODEWORD_IDX                       = (1 << p) - 1;
        always_comb codeword_parity_only[CODEWORD_IDX] = ^(h[p] & codeword_data_only);
    end
    for (genvar k = 0; k < K; k++) begin :gen_zeros
        if (!$onehot(k + 1)) begin :gen_zero_bit
            always_comb codeword_parity_only[k] = 1'b0;
        end
    end

    always_comb o_codeword = codeword_data_only | codeword_parity_only;
endmodule

//# sourceMappingURL=linear_sec_encoder.sv.map
