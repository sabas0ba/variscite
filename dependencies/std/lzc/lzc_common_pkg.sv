package __std_lzc_common_pkg;
    typedef struct packed {
        logic                  all_zero;
        logic [$clog2(4)-1:0] count   ;
    } __result__4;
    typedef struct packed {
        logic                  all_zero;
        logic [$clog2(8)-1:0] count   ;
    } __result__8;
    typedef struct packed {
        logic                  all_zero;
        logic [$clog2(16)-1:0] count   ;
    } __result__16;
    typedef struct packed {
        logic                  all_zero;
        logic [$clog2(32)-1:0] count   ;
    } __result__32;
    typedef struct packed {
        logic                  all_zero;
        logic [$clog2(64)-1:0] count   ;
    } __result__64;

    function automatic __result__4 lzc4(
        input var logic [4-1:0] bits
    ) ;
        __result__4 ret         ;
        ret.all_zero = bits == '0;
        ret.count[1] = bits[1:0] == '0;
        ret.count[0] = !(bits[0] || ((!bits[1]) && bits[2]));
        return ret;
    endfunction

    function automatic __result__8 lzc8(
        input var logic [8-1:0] bits
    ) ;
        __result__4 ret4 [2];
        __result__8 ret     ;

        ret4[0] = lzc4(bits[0*(4)+:(4)]);
        ret4[1] = lzc4(bits[1*(4)+:(4)]);

        ret.all_zero = ret4[0].all_zero && ret4[1].all_zero;
        if (!ret4[0].all_zero) begin
            ret.count = {1'b0, ret4[0].count};
        end else begin
            ret.count = {1'b1, ret4[1].count};
        end

        return ret;
    endfunction

    function automatic __result__16 lzc16(
        input var logic [16-1:0] bits
    ) ;
        __result__4          ret4        [4];
        logic        [4-1:0] any_one        ;
        __result__4          ret_any_one    ;
        __result__16         ret            ;

        for (int i = 0; i < 4; i++) begin
            ret4[i]    = lzc4(bits[i*(4)+:(4)]);
            any_one[i] = !ret4[i].all_zero;
        end
        ret_any_one = lzc4(any_one);

        ret.all_zero = ret_any_one.all_zero;
        ret.count    = {ret_any_one.count, ret4[ret_any_one.count].count};

        return ret;
    endfunction

    function automatic __result__32 lzc32(
        input var logic [32-1:0] bits
    ) ;
        __result__8          ret8        [4];
        logic        [4-1:0] any_one        ;
        __result__4          ret_any_one    ;
        __result__32         ret            ;

        for (int i = 0; i < 4; i++) begin
            ret8[i]    = lzc8(bits[i*(8)+:(8)]);
            any_one[i] = !ret8[i].all_zero;
        end
        ret_any_one = lzc4(any_one);

        ret.all_zero = ret_any_one.all_zero;
        ret.count    = {ret_any_one.count, ret8[ret_any_one.count].count};

        return ret;
    endfunction

    function automatic __result__64 lzc64(
        input var logic [64-1:0] bits
    ) ;
        __result__8          ret8        [8];
        logic        [8-1:0] any_one        ;
        __result__8          ret_any_one    ;
        __result__64         ret            ;

        for (int i = 0; i < 8; i++) begin
            ret8[i]    = lzc8(bits[i*(8)+:(8)]);
            any_one[i] = !ret8[i].all_zero;
        end
        ret_any_one = lzc8(any_one);

        ret.all_zero = ret_any_one.all_zero;
        ret.count    = {ret_any_one.count, ret8[ret_any_one.count].count};

        return ret;
    endfunction
endpackage
//# sourceMappingURL=lzc_common_pkg.sv.map
