package __std_async_fifo_pkg;
    function automatic int unsigned calc_default_depth(
        input var int unsigned stages
    ) ;
        return 2 ** ($clog2(2 * stages) + 1);
    endfunction
endpackage
//# sourceMappingURL=async_fifo_pkg.sv.map
