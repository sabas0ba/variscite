module tb_ddr_alignment;
    localparam [127:0] DATA_A=128'ha55a_5aa5_c33c_3cc3_9669_6996_f00f_0ff0;
    reg clk=0, rst=1, start=0;
    reg [127:0] data=0, expected_data=0;
    reg [1:0] valid=0;
    reg [4:0] sample_index=0;
    wire [31:0] sample;
    wire captured;
    reg [7:0] stream [0:1][0:15];
    reg [127:0] first_word, second_word, pattern;
    reg [15:0] masks [0:15];
    integer offset0, offset1;
    always #5 clk=~clk;

    rv32ima_DdrArrayTimeline #(.MATCH_EXPECTED(1), .ALIGN_SCAN(1)) dut (
        .i_clk(clk), .i_rst(rst), .i_start(start), .i_gate(1'b0),
        .i_burst(2'b11), .i_valid(valid), .i_data(data),
        .i_expected(expected_data), .i_index(sample_index),
        .o_sample(sample), .o_captured(captured)
    );

    initial begin
        for (int trial=0; trial<3; trial++) begin
            @(negedge clk);
            rst=1;
            start=0;
            repeat (2) @(negedge clk);
            rst=0;
            for (int pair_index=0; pair_index<16; pair_index++) begin
                offset0=pair_index%8;
                offset1=7-offset0;
                pattern=pair_index<8 ? DATA_A : ~DATA_A;
                for (int lane=0; lane<2; lane++) begin
                    for (int beat=0; beat<16; beat++) stream[lane][beat]=0;
                    // Construct a serial byte stream independently of the RTL window slices.
                    for (int beat=0; beat<8; beat++)
                        stream[lane][beat+(lane==0 ? offset0 : offset1)] =
                            pattern[16*beat+8*lane+:8] ^ (trial==2 ? 8'hff : 8'h00);
                end
                if (trial==1) stream[0][offset0+7]^=8'h80;
                first_word=0;
                second_word=0;
                for (int beat=0; beat<8; beat++) begin
                    first_word[16*beat+:16]={stream[1][beat],stream[0][beat]};
                    second_word[16*beat+:16]={stream[1][beat+8],stream[0][beat+8]};
                end
                masks[pair_index]=trial==2 ? 16'b0 :
                    {8'(1<<offset1), trial==1 ? 8'b0 : 8'(1<<offset0)};
                @(negedge clk);
                expected_data=pattern;
                start=pair_index==0;
                valid=3;
                data=first_word;
                @(negedge clk);
                start=0;
                valid=0;
                data=second_word;
                @(posedge clk);
            end
            @(negedge clk);
            data='1;
            expected_data=0;
            valid=0;
            if (!captured) $fatal(1,"alignment capture incomplete");
            for (int pair_index=0; pair_index<16; pair_index++) begin
                sample_index=5'(2*pair_index+1);
                #1;
                if (sample[15:0]!==masks[pair_index] || sample[23:16]!==8'h03 || sample[28:27]!==0)
                    $fatal(1,"trial %0d pair %0d expected mask %h got %h",trial,pair_index,masks[pair_index],sample);
            end
        end
        $display("DDR alignment PASS: all 8 offsets, independent lanes, 2 patterns, hidden-bit error, stale data, reset, capture status");
        $finish;
    end
    initial begin
        repeat (200) @(posedge clk);
        $fatal(1,"alignment timeout");
    end
endmodule
