package __std_utils;
    function automatic int unsigned clog2_clipped(
        input var int unsigned x  ,
        input var int unsigned min
    ) ;
        int unsigned result;
        result = $clog2(x);
        return ((result > min) ? ( result ) : ( min ));
    endfunction
endpackage

//# sourceMappingURL=utils.sv.map
