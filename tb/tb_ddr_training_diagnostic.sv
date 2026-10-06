module tb_ddr_training_diagnostic;
    logic clk=0, rst=1, train=0;
    logic [1:0] valid=0, burst=0, ready=0;
    logic [9:0] offsets=0;
    logic [127:0] data=0;
    wire [31:0] status;
    wire [127:0] sample;
    always #5 clk=~clk;
    rv32ima_DdrTrainingDiagnostic dut (
        .i_clk(clk), .i_rst(rst), .i_train(train), .i_valid(valid), .i_burst(burst),
        .i_data(data), .i_ready(ready), .i_offsets(offsets), .o_status(status), .o_sample(sample)
    );
    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        valid=3; burst=3; data='1;
        @(negedge clk);
        if (status!==32'hd3000000 || sample!==0) $fatal(1,"capture outside training");
        train=1; valid=1; burst=2; data=128'h00112233445566778899aabbccddeeff;
        @(negedge clk);
        if (status!==32'hd3000006 || sample!==128'h0011003300550077009900bb00dd00ff) $fatal(1,"lane zero first capture");
        valid=0; burst=1;
        @(negedge clk);
        valid=2; burst=0; data=128'hfedcba98765432100123456789abcdef;
        @(negedge clk);
        ready=3; offsets=10'h041; valid=3; data='1;
        @(negedge clk);
        if (status!==32'hd300107f || sample!==128'hfe11ba3376553277019945bb89ddcdff) $fatal(1,"lane captures or calibration flags");
        train=0; data=0;
        repeat(3) @(negedge clk);
        if (sample!==128'hfe11ba3376553277019945bb89ddcdff) $fatal(1,"later data overwrote first response");
        rst=1; ready=0; offsets=0;
        @(negedge clk);
        if (status!==32'hd3000000 || sample!==0) $fatal(1,"reset did not clear capture");
        $display("DDR training diagnostic PASS: independent lanes, first samples, flags, reset");
        $finish;
    end
    initial begin #1000; $fatal(1,"training diagnostic watchdog"); end
endmodule
