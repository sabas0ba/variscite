module tb_ddr_read_training;
    localparam [127:0] PATTERN = 128'ha55a5aa5c33c3cc396696996f00f0ff0;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1, train = 0;
    logic [127:0] data = 0;
    logic [1:0] valid = 0;
    wire [7:0] offsets;
    wire [1:0] ready, trained, result_valid;
    wire [127:0] result;
    logic [127:0] data_pipe[2];
    logic [1:0] valid_pipe[2];
    always @(posedge clk) begin
        data_pipe[0] <= rst ? 128'b0 : data;
        data_pipe[1] <= rst ? 128'b0 : data_pipe[0];
        valid_pipe[0] <= rst ? 2'b0 : valid;
        valid_pipe[1] <= rst ? 2'b0 : valid_pipe[0];
    end
    rv32ima_DdrReadTraining training (
        .i_clk(clk), .i_rst(rst), .i_train(train), .i_data(data), .i_valid(valid),
        .o_offsets(offsets), .o_ready(ready), .o_trained(trained)
    );
    rv32ima_DdrReadAssembler #(.DYNAMIC(1)) assembler (
        .i_clk(clk), .i_rst(rst), .i_data(data_pipe[1]), .i_valid(valid_pipe[1] & ready),
        .i_offsets(offsets), .o_data(result), .o_valid(result_valid)
    );
    task automatic tick;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic send(input logic [127:0] payload, input int offset0, input int offset1,
                        input logic [1:0] lanes = 3);
        logic [255:0] stream;
        stream = '0;
        for (int lane = 0; lane < 2; lane++)
            for (int beat = 0; beat < 8; beat++)
                stream[16 * (beat + (lane == 0 ? offset0 : offset1)) + 8*lane +: 8] =
                    payload[16*beat + 8*lane +: 8];
        data = stream[127:0]; valid = 0; tick();
        data = stream[255:128]; valid = lanes; tick();
        valid = 0;
        repeat (2) tick();
    endtask
    initial begin
        for (int offset = 0; offset <= 8; offset++) begin
            rst = 1; tick(); rst = 0; train = 1;
            send(PATTERN, offset, 8-offset);
            if (trained != 3 || offsets != {4'(8-offset), 4'(offset)} ||
                result_valid != 3 || result != PATTERN) $fatal(1, "training %0d", offset);
            train = 0;
            send(~PATTERN, offset, 8-offset);
            if (result_valid != 3 || result != ~PATTERN) $fatal(1, "validation pattern");
            // Payload changes must not modify the trained offset or repair errors.
            send(128'h0123456789abcdef_13579bdf2468ace0, offset, 8-offset);
            if (result != 128'h0123456789abcdef_13579bdf2468ace0 ||
                offsets != {4'(8-offset), 4'(offset)}) $fatal(1, "payload dependency");
            train = 1;
            send(PATTERN, (offset+1)%9, offset);
            if (offsets != {4'(8-offset), 4'(offset)}) $fatal(1, "unexpected retraining");
        end
        rst = 1; tick(); rst = 0; train = 1;
        send(PATTERN, 2, 6, 1);
        if (trained != 1 || result_valid != 1) $fatal(1, "lane 0 timing");
        send(PATTERN, 7, 6, 2);
        if (trained != 3 || result_valid != 2 || offsets != 8'h62 || result != PATTERN)
            $fatal(1, "independent lane training");
        rst = 1; tick(); rst = 0; train = 1;
        send(PATTERN ^ 128'h0100, 6, 6);
        if (trained != 1 || result_valid != 1) $fatal(1, "corrupt training accepted");
        send(PATTERN, 6, 6);
        if (trained != 1 || result_valid != 1) $fatal(1, "failed lane retrained");
        rst = 1; tick(); rst = 0; train = 0;
        send(PATTERN, 6, 6);
        if (trained != 0 || result_valid != 0) $fatal(1, "trained without enable");
        $display("DDR read training PASS: offsets, independent lanes, payload, failure, reset");
        $finish;
    end
    initial begin #10000; $fatal(1, "timeout"); end
endmodule
