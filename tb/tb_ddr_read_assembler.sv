module tb_ddr_read_assembler;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic [127:0] data = 0;
    logic [1:0] valid = 0;
    wire [127:0] assembled[9];
    wire [1:0] out_valid[9];
    logic [127:0] previous = 0;
    logic [127:0] expected[9];
    for (genvar offset = 0; offset <= 8; offset++) begin : offsets
        rv32ima_DdrReadAssembler #(.OFFSET0(offset), .OFFSET1(8-offset)) dut (
            .i_clk(clk), .i_rst(rst), .i_data(data), .i_valid(valid), .i_offsets(8'b0),
            .o_data(assembled[offset]), .o_valid(out_valid[offset])
        );
    end
    task automatic step;
        logic [255:0] stream;
        stream = {data, previous};
        for (int offset = 0; offset <= 8; offset++) begin
            for (int lane = 0; lane < 2; lane++) begin
                for (int beat = 0; beat < 8; beat++) begin
                    if (rst) expected[offset][16*beat + 8*lane +: 8] = 0;
                    else if (valid[lane]) expected[offset][16*beat + 8*lane +: 8] =
                        stream[16 * (beat + (lane == 0 ? offset : 8-offset)) + 8*lane +: 8];
                end
            end
        end
        @(posedge clk); #1;
        for (int offset = 0; offset <= 8; offset++) begin
            if (assembled[offset] !== expected[offset]) $fatal(1, "data offset %0d", offset);
            if (out_valid[offset] !== (rst ? 2'b0 : valid)) $fatal(1, "valid timing");
        end
        previous = rst ? 128'b0 : data;
        @(negedge clk);
    endtask
    initial begin
        step(); rst = 0;
        // Exercise each offset with independently valid lanes and changing data.
        for (int cycle = 0; cycle < 256; cycle++) begin
            for (int beat = 0; beat < 8; beat++)
                data[16*beat +: 16] = 16'((cycle * 137 + beat * 997) ^ (cycle << beat));
            valid = 2'(cycle);
            rst = cycle == 123;
            step();
        end
        $display("DDR read assembler PASS: offsets 0..8, independent lanes, hold, reset");
        $finish;
    end
    initial begin #10000; $fatal(1, "timeout"); end
endmodule
