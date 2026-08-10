module __std_ram #(
    parameter int unsigned WORD_SIZE     = 1                                                 ,
    parameter int unsigned ADDRESS_WIDTH = ((WORD_SIZE >= 2) ? ( $clog2(WORD_SIZE) ) : ( 1 )),
    parameter int unsigned DATA_WIDTH    = 8                                                 ,
    parameter type         DATA_TYPE     = logic [DATA_WIDTH-1:0]                            ,
    parameter bit          BUFFER_OUT    = 1'b0                                              ,
    parameter bit          USE_RESET     = 1'b0                                              ,
    parameter DATA_TYPE    INITIAL_VALUE = DATA_TYPE'(0                                     )
) (
    input  var logic                         i_clk ,
    input  var logic                         i_rst ,
    input  var logic                         i_clr ,
    input  var logic                         i_mea ,
    input  var logic                         i_wea ,
    input  var logic     [ADDRESS_WIDTH-1:0] i_adra,
    input  var DATA_TYPE                     i_da  ,
    input  var logic                         i_meb ,
    input  var logic     [ADDRESS_WIDTH-1:0] i_adrb,
    output var DATA_TYPE                     o_qb  
);
    logic [$bits(DATA_TYPE)-1:0] ram_data [WORD_SIZE];
    logic [$bits(DATA_TYPE)-1:0] q                   ;

    if (USE_RESET) begin :g_ram
        always_ff @ (posedge i_clk) begin
            if (i_rst) begin
                ram_data <= '{default: INITIAL_VALUE};
            end else if (i_clr) begin
                ram_data <= '{default: INITIAL_VALUE};
            end else if (i_mea && i_wea) begin
                ram_data[i_adra] <= i_da;
            end
        end
    end else begin :g_ram
        always_ff @ (posedge i_clk) begin
            if (i_mea && i_wea) begin
                ram_data[i_adra] <= i_da;
            end
        end
    end

    always_comb begin
        o_qb = DATA_TYPE'(q);
    end

    if (!BUFFER_OUT) begin :g_out
        always_comb begin
            q = ram_data[i_adrb];
        end
    end else if (USE_RESET) begin :g_out
        always_ff @ (posedge i_clk) begin
            if (i_rst) begin
                q <= INITIAL_VALUE;
            end else if (i_clr) begin
                q <= INITIAL_VALUE;
            end else if (i_meb) begin
                q <= ram_data[i_adrb];
            end
        end
    end else begin :g_out
        always_ff @ (posedge i_clk) begin
            if (i_meb) begin
                q <= ram_data[i_adrb];
            end
        end
    end
endmodule
//# sourceMappingURL=ram.sv.map
