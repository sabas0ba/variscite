module tb_ddr_address_array;
    localparam int PAIRS = 24;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    wire cmd_valid, done, found;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [127:0] write_data, assembled;
    wire [15:0] mask;
    wire [3:0] dq_enable, dqs_enable, odt;
    wire [1:0] assembled_valid, ready;
    wire [7:0] offsets;
    logic [127:0] data = 0, data_pipe[2];
    logic [127:0] memory[int unsigned];
    logic [127:0] written[2*PAIRS];
    logic [1:0] valid = 0, valid_pipe[2];
    logic [255:0] stream;
    int reads = 0, writes = 0, commands = 0, pending = 0, mode = 0;
    int activates = 0, precharges = 0, refreshes = 0, cycles = 0;
    int last_refresh = 0, last_precharge = 0;
    int unsigned open_bank = 0, open_row = 0, write_key = 0;
    bit row_open = 0;

    // Linear x16 geometry: 7 burst-column, 13 row, 3 bank address bits.
    function automatic int unsigned expected_key(input int transaction);
        int pair_index, burst_column;
        pair_index = (transaction / 2) % PAIRS;
        burst_column = transaction % 2;
        case (pair_index)
            0: return 32'(burst_column);
            1,2,3: return (1 << (19 + pair_index)) | 32'(burst_column);
            4,5,6,7,8,9,10,11,12,13,14,15,16:
                return (1 << (3 + pair_index)) | 32'(burst_column);
            17,18,19,20,21,22:
                return (1 << (pair_index - 16)) | 32'(burst_column);
            23: return 32'h7ffffe | 32'(burst_column);
            default: begin $fatal(1, "invalid pair"); return 0; end
        endcase
    endfunction

    function automatic int unsigned physical_key(input int unsigned column);
        int unsigned key;
        key = (open_bank << 20) | (open_row << 7) | (column >> 3);
        // Disconnect each effective address bit independently.
        if (mode >= 1 && mode <= 23) key &= ~(32'b1 << (mode - 1));
        return key;
    endfunction

    rv32ima_DdrArrayProbe #(.READ_HOLD(0), .READ_SEL(6'h24),
                          .MULTI_PATTERN(1), .RETAIN_CHECK(1), .ADDRESS_CHECK(1)) array_probe (
        .i_clk(clk), .i_rst(rst), .i_enable(!rst), .i_burst(valid),
        .i_valid(assembled_valid), .i_data(assembled),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(), .o_sel(), .o_hold(), .o_odt(odt), .o_data(write_data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(dqs_enable), .o_dqs_pattern(),
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
            reads = 0; writes = 0; commands = 0; pending = 0;
            activates = 0; precharges = 0; refreshes = 0; cycles = 0;
            last_refresh = 0; last_precharge = 0; row_open = 0;
            memory.delete();
        end else begin
            cycles++;
            if (cycles - last_refresh > 384) $fatal(1, "refresh deadline exceeded");
            if (last_refresh != 0 && cycles - last_refresh < 256 &&
                (cmd_valid || dq_enable != 0 || dqs_enable != 0 || odt != 0 || done))
                $fatal(1, "activity before REF recovery");
            if (cmd_valid) begin
                case (cmd)
                    3'b011: begin
                        int unsigned expected;
                        expected = expected_key(activates*2);
                        if (row_open || bank != 3'(expected >> 20) ||
                            addr != 14'((expected >> 7) & 8191) || precharges != activates)
                            $fatal(1, "ACT address/order pair=%0d", activates);
                        if (activates != 0 && (refreshes != activates || cycles-last_refresh != 256))
                            $fatal(1, "missing refresh between address pairs");
                        if (activates == PAIRS && mode >= 2 && mode <= 23 && !found)
                            $fatal(1, "address alias should pass immediate readbacks");
                        row_open = 1; open_bank = 32'(bank); open_row = 32'(addr);
                        activates++;
                    end
                    3'b010: begin
                        if (!row_open || addr != 14'h400 || reads != 2*activates)
                            $fatal(1, "PRE address/order");
                        row_open = 0; last_precharge = cycles; precharges++;
                    end
                    3'b001: begin
                        if (row_open || precharges != refreshes+1 || cycles-last_precharge < 3)
                            $fatal(1, "REF ordering/tRP");
                        last_refresh = cycles; refreshes++;
                    end
                    3'b100, 3'b101: begin
                        int transaction;
                        int unsigned logical_key;
                        transaction = cmd == 3'b100 ? commands : reads;
                        logical_key = (open_bank << 20) | (open_row << 7) | (32'(addr) >> 3);
                        if (!row_open || bank != 3'(open_bank) || addr[13:10] != 0 || addr[2:0] != 0 ||
                            logical_key != expected_key(transaction))
                            $fatal(1, "column/bank/row mismatch transaction=%0d", transaction);
                        if (cmd == 3'b100) begin
                            if (commands >= 2*PAIRS || commands != writes)
                                $fatal(1, "unexpected rewrite");
                            write_key = physical_key(32'(addr)); commands++;
                        end
                    end
                    default: $fatal(1, "unexpected command");
                endcase
            end
            if (dq_enable == 15) begin
                if (mask != 0 || commands != writes+1) $fatal(1, "WRITE waveform/order");
                // Every location must carry a distinct full-width pattern.
                for (int previous = 0; previous < writes; previous++)
                    if (written[previous] == write_data) $fatal(1, "duplicate pattern");
                written[writes] = write_data;
                memory[write_key] = write_data;
                writes++;
            end
            if (pending > 0) begin
                if (pending == 2) data <= stream[127:0];
                if (pending == 1) begin
                    data <= stream[255:128];
                    valid <= (mode == 24 && reads == 60) ? 0 : 3;
                end
                pending--;
            end
            if (cmd_valid && cmd == 3'b101) begin
                int unsigned key;
                key = physical_key(32'(addr));
                if (memory.exists(key) == 0 || pending != 0 ||
                    writes != (reads < 2*PAIRS ? ((reads / 2)+1)*2 : 2*PAIRS))
                    $fatal(1, "unwritten READ or unexpected order");
                stream = 0;
                for (int lane = 0; lane < 2; lane++)
                    for (int beat = 0; beat < 8; beat++)
                        stream[16*(beat + (lane == 0 ? 6 : 8)) + 8*lane +: 8] =
                            memory[key][16*beat + 8*lane +: 8];
                if ((mode == 25 && reads == 59) || (mode == 26 && reads == 0))
                    stream[16*6+3] = ~stream[16*6+3];
                reads++; pending = 7;
            end
        end
    end

    initial begin
        for (int scenario = 0; scenario < 27; scenario++) begin
            @(negedge clk); rst = 1; mode = scenario;
            repeat (2) @(negedge clk);
            rst = 0;
            wait(done); @(negedge clk);
            if (found !== (scenario == 0) || reads != 4*PAIRS || writes != 2*PAIRS ||
                commands != writes || activates != 2*PAIRS || precharges != activates ||
                refreshes != 2*PAIRS-1 || cycles != 14073)
                $fatal(1, "address scenario=%0d found=%b cycles=%0d", scenario, found, cycles);
            $display("address scenario=%0d cycles=%0d reads=%0d writes=%0d REF=%0d", scenario, cycles, reads, writes, refreshes);
        end
        $display("DDR address PASS: 23 address bits, final bursts, refresh, retained alias and read fault detection");
        $finish;
    end
    initial begin #5000000; $fatal(1, "timeout"); end
endmodule
