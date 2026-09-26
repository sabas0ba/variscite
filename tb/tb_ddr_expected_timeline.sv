module tb_ddr_expected_timeline;
    localparam [127:0] DATA_A=128'ha55a_5aa5_c33c_3cc3_9669_6996_f00f_0ff0;
    localparam [127:0] LANE0=128'h00ff_00ff_00ff_00ff_00ff_00ff_00ff_00ff;
    reg clk=0, rst=1, start=0;
    reg [127:0] data=0, expected_data=0;
    reg [4:0] sample_index=0;
    wire [31:0] sample;
    wire captured;
    reg [2:0] expected_flags;
    always #5 clk=~clk;

    rv32ima_DdrArrayTimeline #(.MATCH_EXPECTED(1)) dut (
        .i_clk(clk), .i_rst(rst), .i_start(start), .i_gate(1'b0),
        .i_burst(2'b11), .i_valid(2'b11), .i_data(data),
        .i_expected(expected_data), .i_index(sample_index),
        .o_sample(sample), .o_captured(captured)
    );

    initial begin
        repeat (2) @(negedge clk);
        rst=0;
        for (int n=0; n<32; n++) begin
            @(negedge clk);
            start=n==0;
            expected_data=n<16 ? DATA_A : ~DATA_A;
            data=expected_data;
            case (n%8)
                1: data[127]=~data[127];
                2: data[0]=~data[0];
                3: data=~expected_data;
                4: data=expected_data ^ ~LANE0;
                5: data=expected_data ^ LANE0;
                6: data=0;
                default: begin end
            endcase
            @(posedge clk);
        end
        @(negedge clk);
        start=0;
        expected_data=0;
        data='1;
        if (!captured) $fatal(1,"expected-pattern timeline not captured");
        for (int n=0; n<32; n++) begin
            sample_index=5'(n);
            #1;
            case (n%8)
                0,7: expected_flags=3'b111;
                1,4: expected_flags=3'b010;
                2,5: expected_flags=3'b001;
                3,6: expected_flags=3'b000;
            endcase
            if (sample[26:24]!==expected_flags)
                $fatal(1,"cycle %0d expected flags %b got %b",n,expected_flags,sample[26:24]);
        end
        $display("DDR expected timeline PASS: two complex patterns, lane mismatches, stale pattern, immutable capture");
        $finish;
    end
    initial begin
        repeat (100) @(posedge clk);
        $fatal(1,"expected timeline timeout");
    end
endmodule
