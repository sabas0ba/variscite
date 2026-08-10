/// Value counter
module __std_counter #(
    /// Counter width
    parameter int unsigned WIDTH = 2,
    /// Max value of counter
    parameter bit [WIDTH-1:0] MAX_COUNT = '1,
    /// Min value of counter
    parameter bit [WIDTH-1:0] MIN_COUNT = '0,
    /// Initial value of counter
    parameter bit [WIDTH-1:0] INITIAL_COUNT = MIN_COUNT,
    /// Whether counter is wrap around
    parameter bit WRAP_AROUND = 1,
    /// Counter type
    localparam type COUNT = logic [WIDTH-1:0]
) (
    /// Clock
    input var logic i_clk,
    /// Reset
    input var logic i_rst,
    /// Clear counter
    input var logic i_clear,
    /// Set counter to a value
    input var logic i_set,
    /// Value used by i_set
    input var COUNT i_set_value,
    /// Count up
    input var logic i_up,
    /// Count down
    input var logic i_down,
    /// Count value
    output var COUNT o_count,
    /// Count value for the next clock cycle
    output var COUNT o_count_next,
    /// Indicator for wrap around
    output var logic o_wrap_around
);
    function automatic COUNT count_up(
        input var COUNT current_count
    ) ;
        if (current_count == MAX_COUNT) begin
            if (WRAP_AROUND) begin
                return MIN_COUNT;
            end else begin
                return MAX_COUNT;
            end
        end else begin
            return current_count + 1;
        end
    endfunction

    function automatic COUNT count_down(
        input var COUNT current_count
    ) ;
        if (current_count == MIN_COUNT) begin
            if (WRAP_AROUND) begin
                return MAX_COUNT;
            end else begin
                return MIN_COUNT;
            end
        end else begin
            return current_count - 1;
        end
    endfunction

    function automatic logic get_wrap_around_flag(
        input var logic clear        ,
        input var logic set          ,
        input var logic up           ,
        input var logic down         ,
        input var COUNT current_count
    ) ;
        logic [2-1:0] up_down;
        up_down = {up, down};
        if (clear || set) begin
            return '0;
        end else if ((current_count == MAX_COUNT) && (up_down == 2'b10)) begin
            return '1;
        end else if ((current_count == MIN_COUNT) && (up_down == 2'b01)) begin
            return '1;
        end else begin
            return '0;
        end
    endfunction

    function automatic COUNT get_count_next(
        input var logic clear        ,
        input var logic set          ,
        input var COUNT set_value    ,
        input var logic up           ,
        input var logic down         ,
        input var COUNT current_count
    ) ;
        case (1'b1)
            clear          : return INITIAL_COUNT;
            set            : return set_value;
            (up && (!down)): return count_up(current_count);
            (down && (!up)): return count_down(current_count);
            default        : return current_count;
        endcase
    endfunction

    COUNT count     ;
    COUNT count_next;

    always_comb o_count      = count;
    always_comb o_count_next = count_next;

    always_comb count_next = get_count_next(i_clear, i_set, i_set_value, i_up, i_down, count);
    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            count <= INITIAL_COUNT;
        end else begin
            count <= count_next;
        end
    end

    if ((WRAP_AROUND)) begin :g
        always_comb o_wrap_around = get_wrap_around_flag(i_clear, i_set, i_up, i_down, count);
    end else begin :g
        always_comb o_wrap_around = '0;
    end
endmodule
//# sourceMappingURL=counter.sv.map
