module tb_ddr_array_probe;
`ifdef SIMPLE_DATA
    localparam [127:0] DATA_A = 128'b0;
    localparam [7:0] EXPECTED_MATCH0 = 8'h3f;
`else
    localparam [127:0] DATA_A = 128'ha55a_5aa5_c33c_3cc3_9669_6996_f00f_0ff0;
    localparam [7:0] EXPECTED_MATCH0 = 8'h12;
`endif
`ifdef EARLY_GATE
    localparam [31:0] EARLY = 1;
`else
    localparam [31:0] EARLY = 0;
`endif
    localparam [127:0] DATA_B = ~DATA_A;
    reg clk=0, rst=1, enable=0, stale_second=0;
    reg [1:0] valid=0, burst=0;
    reg [127:0] data=0;
    wire cmd_valid, done, found;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, dqs_pattern, match0, match1, raw0, raw1;
    wire [7:0] first_raw0, first_raw1;
    wire [5:0] sel;
    wire [1:0] hold_gate, burst_seen, valid_seen;
    wire [3:0] odt, dq_enable, dqs_enable;
    wire [127:0] write_data;
    wire [15:0] mask;
    integer cycle=0, command_index=0, write_count=0, read_count=0;
    integer write_cycle=-100, read_cycle=-100, pending=0;
    always #5 clk=~clk;

    rv32ima_DdrArrayProbe #(
`ifdef SIMPLE_DATA
        .SIMPLE_DATA(1),
`else
        .SIMPLE_DATA(0),
`endif
        .EARLY_GATE(EARLY)
    ) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_burst(burst), .i_valid(valid), .i_data(data),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(sel), .o_hold(hold_gate),
        .o_odt(odt), .o_data(write_data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(dqs_enable),
        .o_dqs_pattern(dqs_pattern), .o_done(done), .o_found(found),
        .o_burst_seen(burst_seen), .o_valid_seen(valid_seen),
        .o_match0(match0), .o_match1(match1),
        .o_pass_gate0(), .o_pass_gate1(),
        .o_change_gate0(), .o_change_gate1(),
        .o_col0_match0(), .o_col0_match1(), .o_col8_match0(), .o_col8_match1(),
        .o_first_raw0(first_raw0), .o_first_raw1(first_raw1),
        .o_raw0(raw0), .o_raw1(raw1)
    );

    always @(posedge clk) begin
        cycle++;
        valid <= 0;
        burst <= 0;
        data <= 0;
        if (pending>0) begin
            pending--;
            if (pending==0) begin
                valid <= 2'b11;
                burst <= 2'b11;
                data <= (read_count==2 && !stale_second) ? DATA_B : DATA_A;
            end
        end
        if (rst || !enable) begin
            command_index=0;
            write_count=0;
            read_count=0;
            write_cycle=-100;
            read_cycle=-100;
            pending=0;
        end else begin
            if (cmd_valid) begin
                if (bank!=0) $fatal(1,"unexpected bank");
                case (command_index)
                    0: if (cmd!=3'b011 || addr!=0) $fatal(1,"ACT sequence");
                    1: if (cmd!=3'b100 || addr!=0) $fatal(1,"WRITE 0 sequence");
                    2: if (cmd!=3'b100 || addr!=8) $fatal(1,"WRITE 8 sequence");
                    3: if (cmd!=3'b101 || addr!=0) $fatal(1,"READ 0 sequence");
                    4: if (cmd!=3'b101 || addr!=8) $fatal(1,"READ 8 sequence");
                    5: if (cmd!=3'b010 || addr!=14'h400) $fatal(1,"PRE sequence");
                    default: $fatal(1,"extra DDR command");
                endcase
                command_index++;
                if (cmd==3'b100) begin
                    write_count++;
                    write_cycle=cycle;
                end
                if (cmd==3'b101) begin
                    if (cycle-write_cycle<8) $fatal(1,"READ too close to WRITE");
                    read_count++;
                    read_cycle=cycle;
                    pending=5;
                end
            end
            if (cycle-write_cycle==1 && (dqs_enable!=4'b1000 || dq_enable!=0 || odt!=4'hf))
                $fatal(1,"DQS preamble timing");
            if (cycle-write_cycle==2 &&
                (dqs_enable!=4'hf || dq_enable!=4'hf || dqs_pattern!=8'haa ||
                 write_data!=(write_count==1 ? DATA_A : DATA_B) || mask!=0))
                $fatal(1,"WRITE burst timing or data");
            if (cycle-write_cycle==3 && (dqs_enable!=4'b0001 || dq_enable!=0))
                $fatal(1,"DQS postamble timing");
            if (read_gate!=0 && (read_gate!=8'hff || sel!={3'd4,3'd0} ||
                                  cycle-read_cycle!=(EARLY != 0 ? 1 : 2) || dq_enable!=0))
                $fatal(1,"READ gate timing");
            if (done && (cmd_valid || dq_enable!=0 || dqs_enable!=0))
                $fatal(1,"activity after completion");
        end
    end
    task automatic run_case(input bit stale);
        @(negedge clk); rst=1; enable=0; stale_second=stale;
        repeat (2) @(negedge clk);
        rst=0; enable=1;
        for (int n=0; n<100; n++) begin
            @(negedge clk);
            if (done) begin
                if (command_index!=6 || write_count!=2 || read_count!=2 ||
                    valid_seen!=2'b11 || burst_seen!=2'b11 ||
                    match0!=EXPECTED_MATCH0 || match1!=(stale ? 8'h00 : 8'h12) ||
                    found==stale ||
                    (stale ? (first_raw0!=raw0 || first_raw1!=raw1)
                           : (first_raw0==raw0 || first_raw1==raw1)))
                    $fatal(1,"array result mismatch stale=%b cmds=%0d match=%h/%h found=%b",
                        stale,command_index,match0,match1,found);
                return;
            end
        end
        $fatal(1,"array probe timeout");
    endtask
    initial begin
        run_case(0);
        run_case(1);
        $display("DDR array probe PASS: command timing, DQS burst, two patterns, stale-data rejection");
        $finish;
    end
endmodule
