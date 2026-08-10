



module __std_demux
    import __std_selector_pkg::*;
#(
    parameter int unsigned  WIDTH        = 1                                       ,
    parameter type          DATA_TYPE    = logic [WIDTH-1:0]                       ,
    parameter DATA_TYPE     DEFUALT_DATA = DATA_TYPE'(0                           ),
    parameter int unsigned  ENTRIES      = 2                                       ,
    parameter selector_kind KIND         = __std_selector_pkg::selector_kind_BINARY,
    parameter int unsigned  SELECT_WIDTH = calc_select_width(ENTRIES, KIND)    
) (
    input  var logic     [SELECT_WIDTH-1:0] i_select,
    input  var DATA_TYPE                    i_data  ,
    output var DATA_TYPE [ENTRIES-1:0]      o_data  
);


    always_comb begin
        o_data = __std___dispatch__KIND__ENTRIES__DATA_TYPE(i_select, i_data, DEFUALT_DATA);
    end

    function automatic DATA_TYPE [ENTRIES-1:0] __std___dispatch_binary__ENTRIES__DATA_TYPE(
        input var logic     [__std_selector_pkg::calc_binary_select_width(ENTRIES)-1:0] sel         ,
        input var DATA_TYPE                                                             data        ,
        input var DATA_TYPE                                                             default_data
    ) ;
        DATA_TYPE [ENTRIES-1:0] result;

        for (int i = 0; i < ENTRIES; i++) begin
            result[i] = default_data;
        end
        result[sel] = data;

        return result;
    endfunction
    function automatic DATA_TYPE [ENTRIES-1:0] __std___dispatch_vector__ENTRIES__DATA_TYPE(
        input var logic     [ENTRIES-1:0] sel         ,
        input var DATA_TYPE               data        ,
        input var DATA_TYPE               default_data
    ) ;
        DATA_TYPE [ENTRIES-1:0] result;

        for (int i = 0; i < ENTRIES; i++) begin
            if (sel[i]) begin
                result[i] = data;
            end else begin
                result[i] = default_data;
            end
        end

        return result;
    endfunction
    function automatic DATA_TYPE [ENTRIES-1:0] __std___dispatch__KIND__ENTRIES__DATA_TYPE(
        input var logic     [__std_selector_pkg::calc_select_width(ENTRIES, KIND)-1:0] sel         ,
        input var DATA_TYPE                                                            data        ,
        input var DATA_TYPE                                                            default_data
    ) ;
        localparam int unsigned BINARY_SEL_WIDTH = __std_selector_pkg::calc_binary_select_width(ENTRIES);

        if (KIND == __std_selector_pkg::selector_kind_BINARY) begin
            return __std___dispatch_binary__ENTRIES__DATA_TYPE(BINARY_SEL_WIDTH'(sel), data, default_data);
        end else begin
            return __std___dispatch_vector__ENTRIES__DATA_TYPE(ENTRIES'(sel), data, default_data);
        end
    endfunction
endmodule
//# sourceMappingURL=demux.sv.map
