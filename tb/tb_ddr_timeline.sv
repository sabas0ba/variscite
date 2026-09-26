module tb_ddr_timeline #(parameter int unsigned MATCH_ALL=0);
    reg clk=0, rst=1, start=0, ready=0, gate=0;
    reg [1:0] burst=0, valid=0;
    reg [127:0] data=0;
    wire [4:0] sample_index;
    wire [31:0] sample;
    wire captured, tx;
    byte actual, expected;
    int n, nibble;
    reg [3:0] digit;
    always #5 clk=~clk;

    rv32ima_DdrArrayTimeline #(.MATCH_ALL(MATCH_ALL)) recorder (
        .i_clk(clk), .i_rst(rst), .i_start(start), .i_gate(gate),
        .i_burst(burst), .i_valid(valid),
        .i_data(data), .i_index(sample_index),
        .o_sample(sample), .o_captured(captured)
    );
    rv32ima_DdrTimelineUart uart (
        .i_clk(clk), .i_rst(rst), .i_ready(ready),
        .i_sample(sample), .o_index(sample_index), .o_tx(tx)
    );

    function automatic [31:0] expected_word(input int n);
        reg [7:0] flags;
        reg [2:0] match_bits;
        match_bits = MATCH_ALL!=0 ? {(n%8==0), (n==20), (n==20)} : 3'b000;
        flags={(n==2),2'(n),2'(n),match_bits};
        if (MATCH_ALL!=0) begin
            case (n)
                20: return {flags[7:3],3'b011,24'hffffff};
                21: return {flags[7:3],3'b010,24'hffff00};
                22: return {flags[7:3],3'b001,24'h0000ff};
                23: return {flags[7:3],3'b010,24'hffffff};
                24: return {flags[7:3],3'b001,24'hfffeff};
                25: return {flags[7:3],3'b000,24'h000000};
                default: begin end
            endcase
        end
        return {flags,7'b0,1'(n>>2),7'b0,1'(n),7'b0,1'(n>>1)};
    endfunction

    task automatic read_byte(output byte value);
        wait (tx===1'b0);
        repeat (117) @(posedge clk);
        if (tx!==1'b0) $fatal(1,"invalid UART start bit");
        for (int bit_index=0; bit_index<8; bit_index++) begin
            repeat (234) @(posedge clk);
            value[bit_index]=tx;
        end
        repeat (234) @(posedge clk);
        if (tx!==1'b1) $fatal(1,"invalid UART stop bit");
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst=0;
        for (int n=0; n<32; n++) begin
            @(negedge clk);
            start=n==0;
            gate=n==2;
            burst=2'(n);
            valid=2'(n);
            data=0;
            data[0]=1'(n);
            data[1]=1'(n>>2);
            data[8]=1'(n>>1);
            if (MATCH_ALL!=0) begin
                case (n)
                    20: data='1;
                    21: data=128'h00ff_00ff_00ff_00ff_00ff_00ff_00ff_00ff;
                    22: data=128'hff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00;
                    23: data=128'h7fff_ffff_ffff_ffff_ffff_ffff_ffff_ffff;
                    24: data=128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_fffe;
                    25: data=128'h8000_0000_0000_0000_0000_0000_0000_0000;
                    default: begin end
                endcase
            end
            @(posedge clk);
        end
        @(negedge clk);
        start=0;
        if (!captured) $fatal(1,"timeline did not capture 32 cycles");
        ready=1;
        for (int c=0; c<258; c++) begin
            read_byte(actual);
            if (c==0) expected="@";
            else if (c==257) expected=8'h0a;
            else begin
                n=(c-1)/8;
                nibble=(c-1)%8;
                digit=4'(expected_word(n) >> (4*(7-nibble)));
                expected=digit<4'd10 ? 8'h30+{4'b0,digit} : 8'h37+{4'b0,digit};
            end
            if (actual!==expected)
                $fatal(1,"timeline char %0d: got %c expected %c",c,actual,expected);
        end
        $display("DDR timeline PASS: 32 sequential samples and one framed UART transfer");
        $finish;
    end
    initial begin
        repeat (700000) @(posedge clk);
        $fatal(1,"timeline UART timeout");
    end
endmodule
