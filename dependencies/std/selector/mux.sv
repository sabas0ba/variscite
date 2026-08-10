




module __std_mux
    import __std_selector_pkg::*;
#(
    parameter  int unsigned  WIDTH        = 1                                       ,
    parameter  type          DATA_TYPE    = logic [WIDTH-1:0]                       ,
    parameter  int unsigned  ENTRIES      = 2                                       ,
    parameter  selector_kind KIND         = __std_selector_pkg::selector_kind_BINARY,
    localparam int unsigned  SELECT_WIDTH = calc_select_width(ENTRIES, KIND)    
) (
    input  var logic     [SELECT_WIDTH-1:0] i_select,
    input  var DATA_TYPE [ENTRIES-1:0]      i_data  ,
    output var DATA_TYPE                    o_data  
);


    always_comb begin
        o_data = __std___select__KIND__ENTRIES__DATA_TYPE(i_select, i_data);
    end

    function automatic DATA_TYPE __std___select_binary__ENTRIES__DATA_TYPE(
        input var logic     [__std_selector_pkg::calc_binary_select_width(ENTRIES)-1:0] sel ,
        input var DATA_TYPE [ENTRIES-1:0]                                               data
    ) ;
        return data[sel];
    endfunction
    function automatic DATA_TYPE __std___select_vector__ENTRIES__DATA_TYPE(
        input var logic     [ENTRIES-1:0] sel ,
        input var DATA_TYPE [ENTRIES-1:0] data
    ) ;
        localparam int unsigned DEPTH = $clog2(ENTRIES);
        int unsigned               current_n;
        logic        [ENTRIES-1:0] current_s;
        DATA_TYPE    [ENTRIES-1:0] current_d;
        int unsigned               next_n   ;
        logic        [ENTRIES-1:0] next_s   ;
        DATA_TYPE    [ENTRIES-1:0] next_d   ;

        next_n = ENTRIES;
        next_s = sel;
        next_d = data;
        for (int _i = 0; _i < DEPTH; _i++) begin
            current_n = next_n;
            current_s = next_s;
            current_d = next_d;

            next_n = (current_n / 2) + (current_n % 2);
            for (int j = 0; j < next_n; j++) begin
                logic select_even;

                if ((j + 1) == next_n && (current_n % 2) == 1) begin
                    select_even = 1'b1;
                end else begin
                    select_even = current_s[2 * j + 0];
                end

                if (select_even) begin
                    next_s[j] = current_s[2 * j + 0];
                    next_d[j] = current_d[2 * j + 0];
                end else begin
                    next_s[j] = current_s[2 * j + 1];
                    next_d[j] = current_d[2 * j + 1];
                end
            end
        end

        return next_d[0];
    endfunction
    function automatic DATA_TYPE __std___select_onehot__ENTRIES__DATA_TYPE(
        input var logic     [ENTRIES-1:0] sel ,
        input var DATA_TYPE [ENTRIES-1:0] data
    ) ;
        localparam int unsigned DEPTH = $clog2(ENTRIES);
        int unsigned               current_n;
        DATA_TYPE    [ENTRIES-1:0] current_d;
        int unsigned               next_n   ;
        DATA_TYPE    [ENTRIES-1:0] next_d   ;

        next_n = ENTRIES;
        for (int i = 0; i < ENTRIES; i++) begin
            if (sel[i]) begin
                next_d[i] = data[i];
            end else begin
                next_d[i] = DATA_TYPE'(0);
            end
        end

        for (int _i = 0; _i < DEPTH; _i++) begin
            current_n = next_n;
            current_d = next_d;

            next_n = (current_n / 2) + (current_n % 2);
            for (int j = 0; j < next_n; j++) begin
                if ((j + 1) == next_n && (current_n % 2) == 1) begin
                    next_d[j] = current_d[2 * j + 0];
                end else begin
                    next_d[j] = DATA_TYPE'((current_d[2 * j + 0] | current_d[2 * j + 1]));
                end
            end
        end

        return next_d[0];
    endfunction
    function automatic DATA_TYPE __std___select__KIND__ENTRIES__DATA_TYPE(
        input var logic     [__std_selector_pkg::calc_select_width(ENTRIES, KIND)-1:0] sel ,
        input var DATA_TYPE [ENTRIES-1:0]                                              data
    ) ;
        localparam int unsigned BINARY_SEL_WIDTH = __std_selector_pkg::calc_binary_select_width(ENTRIES);

        if (ENTRIES == 1) begin
            return data[0];
        end else if (KIND == __std_selector_pkg::selector_kind_BINARY) begin
            return __std___select_binary__ENTRIES__DATA_TYPE(BINARY_SEL_WIDTH'(sel), data);
        end else if (KIND == __std_selector_pkg::selector_kind_VECTOR) begin
            return __std___select_vector__ENTRIES__DATA_TYPE(ENTRIES'(sel), data);
        end else begin
            return __std___select_onehot__ENTRIES__DATA_TYPE(ENTRIES'(sel), data);
        end
    endfunction
endmodule
//# sourceMappingURL=mux.sv.map
