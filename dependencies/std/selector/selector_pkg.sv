package __std_selector_pkg;
    typedef enum logic [2-1:0] {
        selector_kind_BINARY,
        selector_kind_VECTOR,
        selector_kind_ONEHOT
    } selector_kind;

    function automatic int unsigned calc_binary_select_width(
        input var int unsigned entries
    ) ;
        return ((entries >= 2) ? ( $clog2(entries) ) : ( 1 ));
    endfunction

    function automatic int unsigned calc_select_width(
        input var int unsigned  entries,
        input var selector_kind kind   
    ) ;
        if (kind == selector_kind_BINARY) begin
            return calc_binary_select_width(entries);
        end else begin
            return entries;
        end
    endfunction
endpackage
//# sourceMappingURL=selector_pkg.sv.map
