module tb_ddr_timeline;
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

    rv32ima_DdrArrayTimeline recorder (
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
        flags={(n==2),2'(n),2'(n),3'b000};
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
