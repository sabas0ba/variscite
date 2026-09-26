module tb_ddr_raw_burst;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1, command = 0, gate = 0;
    logic [1:0] burst = 0, valid = 0;
    logic [127:0] data = 0;
    logic [4:0] index = 0;
    wire [31:0] sample;
    wire captured;
    logic [31:0] expected [32];
    rv32ima_DdrRawBurstCapture dut (
        .i_clk(clk), .i_rst(rst), .i_read_command(command),
        .i_gate(gate), .i_burst(burst), .i_valid(valid),
        .i_data(data), .i_index(index), .o_sample(sample), .o_captured(captured)
    );
    task automatic tick;
        @(posedge clk); #1;
        @(negedge clk);
    endtask
    task automatic reset_capture;
        rst = 1; command = 0; valid = 0; gate = 0; burst = 0;
        tick(); rst = 0;
    endtask
    task automatic read_column(input int col);
        logic [127:0] value;
        command = 1; valid = 0; tick(); command = 0;
        for (int cycle = 0; cycle < 3; cycle++) begin
            value = 128'h12345678_89abcdef_76543210_fedcba98 ^
                    (128'h01010101_02020202_04040404_08080808 * 128'(cycle + 3 * col));
            data = value;
            valid = cycle == 1 ? 2'(col + 1) : 0;
            gate = cycle == 0;
            burst = cycle == 1 ? 3 : 0;
            for (int chunk = 0; chunk < 4; chunk++)
                expected[col * 16 + cycle * 4 + chunk] = value[32 * chunk +: 32];
            expected[col * 16 + 12 + cycle] =
                (32'(cycle + 1) << 5) | (32'(gate) << 4) | (32'(burst) << 2) | 32'(valid);
            tick();
        end
    endtask
    initial begin
        foreach (expected[i]) expected[i] = 0;
        reset_capture();
        // A stale valid before READ cannot trigger capture.
        valid = 3; repeat (3) tick(); valid = 0;
        read_column(0);
        if (captured) $fatal(1, "completed before both columns");
        repeat (3) tick();
        read_column(1);
        if (!captured) $fatal(1, "missing completion");
        // Snapshot must remain immutable even with subsequent commands and data.
        command = 1; valid = 3; data = '1; repeat (4) tick();
        for (int i = 0; i < 32; i++) begin
            index = 5'(i); #1;
            if (sample !== expected[i])
                $fatal(1, "word %0d expected %08x got %08x", i, expected[i], sample);
        end
        reset_capture();
        for (int i = 0; i < 32; i++) begin
            index = 5'(i); #1;
            if (sample !== 0) $fatal(1, "reset left stale sample");
        end
        // Missing the first response must not produce a complete two-column frame.
        command = 1; tick(); command = 0; repeat (4) tick();
        read_column(1);
        if (captured) $fatal(1, "missing first column accepted");
        repeat (260) tick();
        if (captured) $fatal(1, "timeout fabricated capture");
        $display("DDR raw burst capture PASS");
        $finish;
    end
    initial begin #10000; $fatal(1, "timeout"); end
endmodule
