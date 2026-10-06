module tb_ddr_mask_array;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    wire cmd_valid, done, found;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [127:0] write_data, assembled;
    wire [15:0] mask;
    wire [3:0] dq_enable;
    wire [1:0] assembled_valid, ready;
    wire [9:0] offsets;
    logic [127:0] data = 0, data_pipe[2], memory[16], original[16];
    logic [1:0] valid = 0, valid_pipe[3];
    logic [255:0] stream;
    int reads = 0, writes = 0, commands = 0, pending = 0, mode = 0;
    int activates = 0, precharges = 0, cycles = 0;
    logic [15:0] visited = 0;

    function automatic int location(input int transaction);
        return (transaction / 4) * 2 + (transaction % 2);
    endfunction

    rv32ima_DdrArrayProbe #(.READ_HOLD(0), .READ_SEL(6'h24),
                          .MULTI_PATTERN(1), .BYTE_MASK(1)) array_probe (
        .i_clk(clk), .i_rst(rst), .i_enable(!rst), .i_burst(valid),
        .i_valid(assembled_valid), .i_data(assembled),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(), .o_sel(), .o_hold(), .o_odt(), .o_data(write_data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(), .o_dqs_pattern(),
        .o_done(done), .o_found(found), .o_burst_seen(), .o_valid_seen(),
        .o_match0(), .o_match1(), .o_pass_gate0(), .o_pass_gate1(),
        .o_change_gate0(), .o_change_gate1(), .o_col0_match0(), .o_col0_match1(),
        .o_col8_match0(), .o_col8_match1(), .o_first_raw0(), .o_first_raw1(),
        .o_raw0(), .o_raw1(), .o_expected()
    );
    rv32ima_DdrReadTraining training (
        .i_clk(clk), .i_rst(rst), .i_train(reads == 1), .i_data(data), .i_valid(valid),
        .o_offsets(offsets), .o_ready(ready), .o_trained()
    );
    rv32ima_DdrReadAssembler #(.DYNAMIC(1)) assembler (
        .i_clk(clk), .i_rst(rst), .i_data(data_pipe[1]), .i_valid(valid_pipe[2] & ready),
        .i_offsets(offsets), .o_data(assembled), .o_valid(assembled_valid)
    );

    always @(posedge clk) begin
        data_pipe[0] <= rst ? 128'b0 : data;
        data_pipe[1] <= rst ? 128'b0 : data_pipe[0];
        valid_pipe[0] <= rst ? 2'b0 : valid;
        valid_pipe[1] <= rst ? 2'b0 : valid_pipe[0];
        valid_pipe[2] <= rst ? 2'b0 : valid_pipe[1];
        valid <= 0;
        data <= 0;
        if (rst) begin
            reads = 0; writes = 0; commands = 0; pending = 0;
            activates = 0; precharges = 0; cycles = 0; visited = 0;
        end else begin
            cycles++;
            if (cmd_valid) begin
                case (cmd)
                    3'b011: begin
                        if (bank != 3'(activates) || addr != 14'(activates) ||
                            precharges != activates) $fatal(1, "ACT ordering/address");
                        activates++;
                    end
                    3'b010: begin
                        if (addr != 14'h400 || reads != 4*activates || writes != reads)
                            $fatal(1, "PRE before all readbacks");
                        precharges++;
                    end
                    3'b100: begin
                        if (bank != 3'(commands / 4) || addr != 14'((commands % 2)*8) ||
                            commands != writes) $fatal(1, "WRITE ordering/address");
                        commands++;
                    end
                    3'b101: begin
                        if (bank != 3'(reads / 4) || addr != 14'((reads % 2)*8) ||
                            writes != ((reads / 2) + 1)*2 || pending != 0)
                            $fatal(1, "READ ordering/address");
                    end
                    default: $fatal(1, "unexpected command");
                endcase
            end
            if (dq_enable == 15) begin
                int index, selected;
                logic [15:0] applied_mask;
                index = location(writes);
                selected = (writes / 4) + (writes % 2)*8;
                if (writes >= 32 || commands != writes + 1) $fatal(1, "extra write");
                if (writes % 4 < 2) begin
                    if (mask != 0) $fatal(1, "initial write must enable all bytes");
                    original[index] = write_data;
                end else begin
                    if (mask != ~(16'b1 << selected) || write_data != ~original[index])
                        $fatal(1, "single-byte mask/data");
                    visited[selected] = 1;
                end
                applied_mask = mask;
                // Only damage one middle pair, so later successful pairs cannot hide failure.
                if (writes / 4 == 3 && writes % 4 >= 2) begin
                    case (mode)
                        1: applied_mask = 0;      // DM ignored
                        2: applied_mask = '1;     // selected byte remains stale
                        3: for (int b = 0; b < 16; b++) applied_mask[b] = mask[b ^ 1];
                        4: applied_mask = {mask[13:0], mask[15:14]}; // wrong DQS beat
                        default: begin end
                    endcase
                end
                for (int b = 0; b < 16; b++)
                    if (!applied_mask[b]) memory[index][8*b +: 8] = write_data[8*b +: 8];
                writes++;
            end
            if (pending > 0) begin
                if (pending == 2) data <= stream[127:0];
                if (pending == 1) begin
                    data <= stream[255:128];
                    valid <= 3;
                end
                pending--;
            end
            if (cmd_valid && cmd == 3'b101) begin
                stream = 0;
                for (int lane = 0; lane < 2; lane++)
                    for (int beat = 0; beat < 8; beat++)
                        stream[16*(beat + (lane == 0 ? 6 : 8)) + 8*lane +: 8] =
                            memory[location(reads)][16*beat + 8*lane +: 8];
                // Initial readback failure must persist through the following masked writes.
                if ((mode == 5 && reads == 13) || (mode == 6 && reads == 14))
                    stream[16*6 + 3] = ~stream[16*6 + 3];
                reads++;
                pending = 7;
            end
        end
    end

    initial begin
        for (int scenario = 0; scenario < 7; scenario++) begin
            @(negedge clk); rst = 1; mode = scenario;
            repeat (2) @(negedge clk);
            rst = 0;
            wait(done); @(negedge clk);
            if (found !== (scenario == 0) || reads != 32 || writes != 32 || commands != 32 ||
                activates != 8 || precharges != 8 || visited != 16'hffff || cycles > 770)
                $fatal(1, "mask scenario=%0d found=%b cycles=%0d", scenario, found, cycles);
            $display("mask scenario=%0d cycles=%0d reads=%0d writes=%0d", scenario, cycles, reads, writes);
        end
        $display("DDR byte mask PASS: all 16 positions, preserved bytes, DM lane/beat faults, sticky read errors");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
