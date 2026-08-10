module __std_slicer #(
    parameter int unsigned WIDTH           = 1                ,
    parameter type         TYPE            = logic [WIDTH-1:0],
    parameter int unsigned STAGES          = 1                ,
    parameter bit          ASCENDING_ORDER = 1'b1             ,
    parameter bit          FULL_BANDWIDTH  = 1'b1             ,
    parameter bit          DISABLE_MBFF    = 1'b0             ,
    parameter bit          USE_RESET       = 1'b0         
) (
    input  var logic i_clk  ,
    input  var logic i_rst  ,
    output var logic o_ready,
    input  var logic i_valid,
    input  var TYPE  i_data ,
    input  var logic i_ready,
    output var logic o_valid,
    output var TYPE  o_data 
);
    localparam int unsigned W = $bits(TYPE);

    logic         ready [STAGES + 1];
    logic         valid [STAGES + 1];
    logic [W-1:0] data  [STAGES + 1];

    if (ASCENDING_ORDER) begin :g
        always_comb begin
            o_ready  = ready[0];
            valid[0] = i_valid;
            data[0]  = i_data;
        end

        always_comb begin
            ready[STAGES] = i_ready;
            o_valid       = valid[STAGES];
            o_data        = data[STAGES];
        end

        for (genvar i = 0; i < STAGES; i++) begin :g
            localparam bit RESET = USE_RESET && (i == (STAGES - 1));

            if (FULL_BANDWIDTH) begin :g
                __std_slicer_unit_fb #(
                    .WIDTH        (W           ),
                    .DISABLE_MBFF (DISABLE_MBFF),
                    .USE_RESET    (RESET       )
                ) u_slicer (
                    .i_clk   (i_clk       ),
                    .i_rst   (i_rst       ),
                    .o_ready (ready[i + 0]),
                    .i_valid (valid[i + 0]),
                    .i_data  (data[i + 0] ),
                    .i_ready (ready[i + 1]),
                    .o_valid (valid[i + 1]),
                    .o_data  (data[i + 1] )
                );
            end else begin :g
                __std_slicer_unit_hb #(
                    .WIDTH        (W           ),
                    .DISABLE_MBFF (DISABLE_MBFF),
                    .USE_RESET    (RESET       )
                ) u_slicer (
                    .i_clk   (i_clk       ),
                    .i_rst   (i_rst       ),
                    .o_ready (ready[i + 0]),
                    .i_valid (valid[i + 0]),
                    .i_data  (data[i + 0] ),
                    .i_ready (ready[i + 1]),
                    .o_valid (valid[i + 1]),
                    .o_data  (data[i + 1] )
                );
            end
        end
    end else begin :g
        always_comb begin
            o_ready       = ready[STAGES];
            valid[STAGES] = i_valid;
            data[STAGES]  = i_data;
        end

        always_comb begin
            ready[0] = i_ready;
            o_valid  = valid[0];
            o_data   = data[0];
        end

        for (genvar i = 0; i < STAGES; i++) begin :g
            localparam bit RESET = USE_RESET && (i == 0);

            if (FULL_BANDWIDTH) begin :g
                __std_slicer_unit_fb #(
                    .WIDTH        (W           ),
                    .DISABLE_MBFF (DISABLE_MBFF),
                    .USE_RESET    (RESET       )
                ) u_slicer (
                    .i_clk   (i_clk       ),
                    .i_rst   (i_rst       ),
                    .o_ready (ready[i + 1]),
                    .i_valid (valid[i + 1]),
                    .i_data  (data[i + 1] ),
                    .i_ready (ready[i + 0]),
                    .o_valid (valid[i + 0]),
                    .o_data  (data[i + 0] )
                );
            end else begin :g
                __std_slicer_unit_hb #(
                    .WIDTH        (W           ),
                    .DISABLE_MBFF (DISABLE_MBFF),
                    .USE_RESET    (RESET       )
                ) u_slicer (
                    .i_clk   (i_clk       ),
                    .i_rst   (i_rst       ),
                    .o_ready (ready[i + 1]),
                    .i_valid (valid[i + 1]),
                    .i_data  (data[i + 1] ),
                    .i_ready (ready[i + 0]),
                    .o_valid (valid[i + 0]),
                    .o_data  (data[i + 0] )
                );
            end
        end
    end
endmodule

//# sourceMappingURL=slicer.sv.map
