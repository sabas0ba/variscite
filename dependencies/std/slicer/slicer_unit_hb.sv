module __std_slicer_unit_hb #(
    parameter int unsigned WIDTH        = 1   ,
    parameter bit          DISABLE_MBFF = 1'b0,
    parameter bit          USE_RESET    = 1'b0
) (
    input  var logic             i_clk  ,
    input  var logic             i_rst  ,
    output var logic             o_ready,
    input  var logic             i_valid,
    input  var logic [WIDTH-1:0] i_data ,
    input  var logic             i_ready,
    output var logic             o_valid,
    output var logic [WIDTH-1:0] o_data 
);
    logic valid;

    always_comb begin
        o_ready = !valid;
        o_valid = valid;
    end

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            valid <= '0;
        end else if (!valid) begin
            valid <= i_valid;
        end else if (i_ready) begin
            valid <= '0;
        end
    end

    if (DISABLE_MBFF) begin :g_data
        logic [WIDTH-1:0] data;

        always_comb begin
            o_data = data;
        end

        if (USE_RESET) begin :g
            always_ff @ (posedge i_clk) begin
                if (i_rst) begin
                    data <= '0;
                end else if ((!valid) && i_valid) begin
                    data <= i_data;
                end
            end
        end else begin :g
            always_ff @ (posedge i_clk) begin
                if ((!valid) && i_valid) begin
                    data <= i_data;
                end
            end
        end
    end else begin :g
        for (genvar i = 0; i < WIDTH; i++) begin :g
            logic d;

            always_comb begin
                o_data[i] = d;
            end

            if (USE_RESET) begin :g
                always_ff @ (posedge i_clk) begin
                    if (i_rst) begin
                        d <= '0;
                    end else if ((!valid) && i_valid) begin
                        d <= i_data[i];
                    end
                end
            end else begin :g
                always_ff @ (posedge i_clk) begin
                    if ((!valid) && i_valid) begin
                        d <= i_data[i];
                    end
                end
            end
        end
    end
endmodule
//# sourceMappingURL=slicer_unit_hb.sv.map
