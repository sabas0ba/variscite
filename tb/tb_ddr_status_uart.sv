module tb_ddr_status_uart;
    reg clk=0, rst=1, extra=1;
    wire tx;
    byte actual, expected;
    always #5 clk=~clk;

    rv32ima_TangDdrStatusUart #(.GAP_BITS(8)) dut (
        .i_clk(clk), .i_rst(rst), .i_status(4'd6),
        .i_debug_enable(1'b1), .i_debug_extra(extra),
        .i_debug0(8'h12), .i_debug1(8'hab),
        .i_debug2(8'hcd), .i_debug3(8'hef), .o_tx(tx)
    );

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
        repeat (4) @(negedge clk);
        rst=0;
        for (int i=0; i<9; i++) begin
            read_byte(actual);
            case (i)
                0: expected="M";
                1: expected="1";
                2: expected="2";
                3: expected="A";
                4: expected="B";
                5: expected="C";
                6: expected="D";
                7: expected="E";
                8: expected="F";
            endcase
            if (actual!==expected)
                $fatal(1,"extended UART byte %0d: got %c expected %c",i,actual,expected);
        end
        extra=0;
        for (int i=0; i<5; i++) begin
            read_byte(actual);
            case (i)
                0: expected="M";
                1: expected="1";
                2: expected="2";
                3: expected="A";
                4: expected="B";
            endcase
            if (actual!==expected)
                $fatal(1,"ordinary UART byte %0d: got %c expected %c",i,actual,expected);
        end
        $display("DDR status UART PASS: 9-byte delay and 5-byte MPR frames");
        $finish;
    end
    initial begin
        repeat (50000) @(posedge clk);
        $fatal(1,"UART frame timeout");
    end
endmodule
