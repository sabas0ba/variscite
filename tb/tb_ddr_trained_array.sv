module tb_ddr_trained_array #(parameter MULTI = 0, parameter RETAIN = 0);
    localparam ROUNDS = MULTI ? 8 : 1;
    localparam READ_ROUNDS = ROUNDS * (RETAIN ? 2 : 1);
    localparam int BANKS[8] = '{0, 1, 2, 4, 0, 0, 0, 0};
    localparam int ROWS[8] = '{0, 0, 0, 0, 1, 2, 4, 8};
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    wire cmd_valid, done, found;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [127:0] write_data, assembled;
    wire [3:0] dq_enable;
    wire [1:0] assembled_valid, ready, trained;
    wire [7:0] offsets;
    logic [127:0] data = 0, data_pipe[2], memory[16];
    logic [127:0] written[16];
    logic [1:0] valid = 0, valid_pipe[2];
    logic [255:0] stream;
    int reads = 0, writes = 0, pending = 0, mode = 0;
    int activates = 0, precharges = 0, cycles = 0;
    function automatic int location(input int transaction);
        int pair_index;
        pair_index = (transaction / 2) % ROUNDS;
        if ((mode == 5 && pair_index < 4) || (mode == 6 && pair_index >= 4))
            return transaction % 2;
        return (transaction % (2*ROUNDS));
    endfunction
    rv32ima_DdrArrayProbe #(.READ_HOLD(0), .READ_SEL(6'h24), .MULTI_PATTERN(MULTI),
                          .RETAIN_CHECK(RETAIN)) array_probe (
        .i_clk(clk), .i_rst(rst), .i_enable(!rst), .i_burst(valid),
        .i_valid(assembled_valid), .i_data(assembled),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(), .o_sel(), .o_hold(), .o_odt(), .o_data(write_data), .o_mask(),
        .o_dq_enable(dq_enable), .o_dqs_enable(), .o_dqs_pattern(),
        .o_done(done), .o_found(found), .o_burst_seen(), .o_valid_seen(),
        .o_match0(), .o_match1(), .o_pass_gate0(), .o_pass_gate1(),
        .o_change_gate0(), .o_change_gate1(), .o_col0_match0(), .o_col0_match1(),
        .o_col8_match0(), .o_col8_match1(), .o_first_raw0(), .o_first_raw1(),
        .o_raw0(), .o_raw1(), .o_expected()
    );
    rv32ima_DdrReadTraining training (
        .i_clk(clk), .i_rst(rst), .i_train(reads == 1), .i_data(data), .i_valid(valid),
        .o_offsets(offsets), .o_ready(ready), .o_trained(trained)
    );
    rv32ima_DdrReadAssembler #(.DYNAMIC(1)) assembler (
        .i_clk(clk), .i_rst(rst), .i_data(data_pipe[1]), .i_valid(valid_pipe[1] & ready),
        .i_offsets(offsets), .o_data(assembled), .o_valid(assembled_valid)
    );
    always @(posedge clk) begin
        data_pipe[0] <= rst ? 128'b0 : data;
        data_pipe[1] <= rst ? 128'b0 : data_pipe[0];
        valid_pipe[0] <= rst ? 2'b0 : valid;
        valid_pipe[1] <= rst ? 2'b0 : valid_pipe[0];
        valid <= 0;
        data <= 0;
        if (rst) begin
            reads = 0; writes = 0; pending = 0;
            activates = 0; precharges = 0; cycles = 0;
        end else begin
            cycles++;
            if (cmd_valid && cmd == 3'b011) begin
                // Immediate readback cannot detect these aliases; the second pass must.
                if (RETAIN && mode >= 5 && activates == ROUNDS && !found)
                    $fatal(1, "alias scenario failed before retained-data verification");
                if (bank != 3'(RETAIN ? BANKS[activates % ROUNDS] : activates % ROUNDS) ||
                    addr != 14'(RETAIN ? ROWS[activates % ROUNDS] : activates % ROUNDS))
                    $fatal(1, "ACT bank/row");
                activates++;
            end
            if (cmd_valid && cmd == 3'b010) begin
                if (addr != 14'h400) $fatal(1, "PRE all banks");
                precharges++;
            end
            if (dq_enable == 15) begin
                if (writes >= 2*ROUNDS) $fatal(1, "unexpected rewrite");
                if (writes >= 2 && (writes % 2 == 0) && write_data == written[writes-2])
                    $fatal(1, "repeated pattern");
                if ((writes % 2 == 1) && write_data != ~written[writes-1])
                    $fatal(1, "missing complement");
                written[writes] = write_data;
                memory[location(writes)] = write_data;
                writes++;
            end
            if (pending > 0) begin
                if (pending == 2) data <= stream[127:0];
                if (pending == 1) begin
                    data <= stream[255:128];
                    valid <= (mode == 4 && reads == 8) ? 0 : 3;
                end
                pending--;
            end
            if (cmd_valid && cmd == 3'b101) begin
                if (writes != (reads < 2*ROUNDS ? ((reads / 2) + 1) * 2 : 2*ROUNDS) ||
                    bank != 3'(RETAIN ? BANKS[(reads / 2) % ROUNDS] : (reads / 2) % ROUNDS) ||
                    addr != ((reads % 2) == 0 ? 14'd0 : 14'd8)) $fatal(1, "READ order/address");
                stream = 0;
                for (int lane = 0; lane < 2; lane++)
                    for (int beat = 0; beat < 8; beat++)
                        stream[16*(beat + (lane == 0 ? 6 : 8)) + 8*lane +: 8] =
                            memory[(mode == 1 && reads == 1) ? 0 : location(reads)][16*beat + 8*lane +: 8];
                if (mode == 2 && reads == 0) stream[16*6 + 3] = ~stream[16*6 + 3];
                if (mode == 3 && reads == 7) stream[16*9 + 5] = ~stream[16*9 + 5];
                reads++;
                pending = 7;
            end
        end
    end
    initial begin
        for (int scenario = 0; scenario < (RETAIN ? 7 : MULTI ? 5 : 3); scenario++) begin
            @(negedge clk); rst = 1; mode = scenario;
            repeat (2) @(negedge clk);
            rst = 0;
            wait(done); @(negedge clk);
            if (found !== (scenario == 0) || reads != 2*READ_ROUNDS || writes != 2*ROUNDS ||
                activates != READ_ROUNDS || precharges != READ_ROUNDS || cycles > 700)
                $fatal(1, "trained array scenario=%0d found=%b", scenario, found);
            $display("scenario=%0d cycles=%0d reads=%0d writes=%0d", scenario, cycles, reads, writes);
        end
        $display("DDR trained array PASS: rounds=%0d retain=%0d, latency, offsets, stale/corrupt/missing/alias rejection", ROUNDS, RETAIN);
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
