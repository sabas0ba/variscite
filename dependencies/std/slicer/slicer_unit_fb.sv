module __std_slicer_unit_fb #(
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
    logic valid_0;
    logic valid_1;

    always_comb begin
        o_ready = !valid_1;
        o_valid = valid_0;
    end

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            valid_0 <= '0;
        end else if (!valid_0 || i_ready) begin
            valid_0 <= i_valid || valid_1;
        end
    end

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            valid_1 <= '0;
        end else if (i_ready) begin
            valid_1 <= '0;
        end else if (valid_0 && !valid_1) begin
            valid_1 <= i_valid;
        end
    end

    if (!DISABLE_MBFF) begin :g_data
        logic [WIDTH-1:0] data_0;
        logic [WIDTH-1:0] data_1;

        always_comb begin
            o_data = data_0;
        end

        if (USE_RESET) begin :g
            always_ff @ (posedge i_clk) begin
                if (i_rst) begin
                    data_0 <= '0;
                end else if (!valid_0 || i_ready) begin
                    if (valid_1) begin
                        data_0 <= data_1;
                    end else if (i_valid) begin
                        data_0 <= i_data;
                    end
                end
            end
        end else begin :g
            always_ff @ (posedge i_clk) begin
                if (!valid_0 || i_ready) begin
                    if (valid_1) begin
                        data_0 <= data_1;
                    end else if (i_valid) begin
                        data_0 <= i_data;
                    end
                end
            end
        end

        always_ff @ (posedge i_clk) begin
            if (valid_0 && (!valid_1) && (!i_ready) && i_valid) begin
                data_1 <= i_data;
            end
        end
    end else begin :g
        for (genvar i = 0; i < WIDTH; i++) begin :g
            logic d_0;
            logic d_1;

            always_comb begin
                o_data[i] = d_0;
            end

            if (USE_RESET) begin :g
                always_ff @ (posedge i_clk) begin
                    if (i_rst) begin
                        d_0 <= '0;
                    end else if (!valid_0 || i_ready) begin
                        if (valid_1) begin
                            d_0 <= d_1;
                        end else if (i_valid) begin
                            d_0 <= i_data[i];
                        end
                    end
                end
            end else begin :g
                always_ff @ (posedge i_clk) begin
                    if (!valid_0 || i_ready) begin
                        if (valid_1) begin
                            d_0 <= d_1;
                        end else if (i_valid) begin
                            d_0 <= i_data[i];
                        end
                    end
                end
            end

            always_ff @ (posedge i_clk) begin
                if (valid_0 && (!valid_1) && (!i_ready) && i_valid) begin
                    d_1 <= i_data[i];
                end
            end
        end
    end
endmodule
//# sourceMappingURL=slicer_unit_fb.sv.map
