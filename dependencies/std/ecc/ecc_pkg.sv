package __std_ecc_pkg;
    function automatic int unsigned get_check_width(
        input var int unsigned data_width
    ) ;
        if (data_width == 0) begin
            return 0;
        end

        if (data_width <= __std_hamming_11_5_pkg::DATA_WIDTH) begin
            return __std_hamming_11_5_pkg::CHECK_WIDTH;
        end else if (data_width <= __std_hamming_26_6_pkg::DATA_WIDTH) begin
            return __std_hamming_26_6_pkg::CHECK_WIDTH;
        end else if (data_width <= __std_hamming_57_7_pkg::DATA_WIDTH) begin
            return __std_hamming_57_7_pkg::CHECK_WIDTH;
        end else if (data_width <= __std_hamming_120_8_pkg::DATA_WIDTH) begin
            return __std_hamming_120_8_pkg::CHECK_WIDTH;
        end else if (data_width <= __std_hamming_247_9_pkg::DATA_WIDTH) begin
            return __std_hamming_247_9_pkg::CHECK_WIDTH;
        end else begin
            return 0;
        end
    endfunction

    function automatic int unsigned get_code_width(
        input var int unsigned data_width
    ) ;
        return data_width + get_check_width(data_width);
    endfunction
endpackage
//# sourceMappingURL=ecc_pkg.sv.map
