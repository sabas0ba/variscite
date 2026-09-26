module tb_ddr_array_gate_scan #(
    parameter int unsigned SAME_DATA=0,
    parameter int unsigned EARLY_GATE=0,
    parameter int unsigned PHASE_SCAN=0,
    parameter int unsigned READ_HOLD=1,
    parameter int unsigned PHASE_ALIGN=0
);
    localparam [127:0] DATA_A = 128'ha55a_5aa5_c33c_3cc3_9669_6996_f00f_0ff0;
    localparam [127:0] DATA_B = SAME_DATA!=0 ? DATA_A : ~DATA_A;
    reg clk=0, rst=1, enable=0, stale_second=0, corrupt_lane=0;
    reg mismatch_offset=0, tail_pending=0;
    reg [127:0] tail_data=0, response_data;
    integer response_shift;
    reg [1:0] valid=0, burst=0;
    reg [127:0] data=0;
    wire cmd_valid, done, found;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, gate0, gate1, change0, change1;
    wire [7:0] col0_match0, col0_match1, col8_match0, col8_match1;
    wire [127:0] write_data;
    wire [127:0] expected_data;
    wire [5:0] sel;
    wire [1:0] hold_gate;
    integer cycle=0, read_cycle=-100, write_cycle=-100;
    integer read_count=0, write_count=0, pre_count=0;
    always #5 clk=~clk;

    rv32ima_DdrArrayProbe #(.GATE_SCAN(1), .SAME_DATA(SAME_DATA), .EARLY_GATE(EARLY_GATE), .PHASE_SCAN(PHASE_SCAN), .READ_HOLD(READ_HOLD), .PHASE_ALIGN(PHASE_ALIGN)) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_burst(burst), .i_valid(valid), .i_data(data),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(sel), .o_hold(hold_gate), .o_odt(),
        .o_data(write_data), .o_mask(), .o_dq_enable(), .o_dqs_enable(),
        .o_dqs_pattern(), .o_done(done), .o_found(found),
        .o_burst_seen(), .o_valid_seen(), .o_match0(), .o_match1(),
        .o_pass_gate0(gate0), .o_pass_gate1(gate1),
        .o_change_gate0(change0), .o_change_gate1(change1),
        .o_col0_match0(col0_match0), .o_col0_match1(col0_match1),
        .o_col8_match0(col8_match0), .o_col8_match1(col8_match1),
        .o_first_raw0(), .o_first_raw1(), .o_raw0(), .o_raw1(), .o_expected(expected_data)
    );

    always @(posedge clk) begin
        cycle++;
        valid <= 0;
        burst <= 0;
        data <= tail_pending ? tail_data : 128'b0;
        tail_pending <= 0;
        if (rst || !enable) begin
            read_count=0;
            write_count=0;
            pre_count=0;
            read_cycle=-100;
            write_cycle=-100;
        end else begin
            if (hold_gate!=(cmd_valid && cmd==3'b101 && READ_HOLD!=0 ? 2'b11 : 2'b00))
                $fatal(1,"READ hold mismatch");
            if (cmd_valid) begin
                if (bank!=0) $fatal(1,"unexpected bank");
                case (cmd)
                    3'b011: if (write_count!=0 || read_count!=0 || addr!=0)
                        $fatal(1,"ACT sequence");
                    3'b100: begin
                        if (write_count>=2 || addr!=(write_count==0 ? 0 : 8))
                            $fatal(1,"WRITE sequence");
                        write_count++;
                        write_cycle=cycle;
                    end
                    3'b101: begin
                        if (write_count!=2 || read_count>=16 ||
                            addr!=(read_count%2==0 ? 0 : 8))
                            $fatal(1,"READ sequence");
                        read_count++;
                        read_cycle=cycle;
                    end
                    3'b010: begin
                        if (read_count!=16 || pre_count!=0 || addr!=14'h400)
                            $fatal(1,"PRE sequence");
                        pre_count++;
                    end
                    default: $fatal(1,"unexpected DDR command");
                endcase
            end
            if (cycle-write_cycle==2 && write_data!=(write_count==1 ? DATA_A : DATA_B))
                $fatal(1,"WRITE burst data mismatch");
            if (read_gate!=0) begin
                if (read_gate!=8'hff || read_count==0 ||
                    cycle-read_cycle!=(PHASE_SCAN!=0 ? 0 : (read_count-1)/2)+(EARLY_GATE!=0 ? 1 : 2) ||
                    expected_data!=(read_count%2==1 ? DATA_A : DATA_B))
                    $fatal(1,"gate schedule at read %0d",read_count);
                if (PHASE_SCAN!=0 && sel!={3'((read_count-1)/2),3'((read_count-1)/2)})
                    $fatal(1,"phase selection at read %0d",read_count);
                response_shift=PHASE_ALIGN!=0 ? (mismatch_offset && read_count%2==0 ? 64 : 32) : 0;
                // Only lane0 at candidate 3 and lane1 at candidate 5 are valid.
                if ((read_count-1)/2==3) begin
                    valid <= 2'b01;
                    burst <= 2'b01;
                    response_data = (read_count%2==1 || stale_second ? DATA_A : DATA_B) ^
                        (corrupt_lane ? 128'h80 : 128'b0);
                    data <= response_data << response_shift;
                    tail_data <= response_data >> (128-response_shift);
                    tail_pending <= PHASE_ALIGN!=0;
                end
                if ((read_count-1)/2==5) begin
                    valid <= 2'b10;
                    burst <= 2'b10;
                    response_data = (read_count%2==1 || stale_second ? DATA_A : DATA_B) ^
                        (corrupt_lane ? 128'h8000 : 128'b0);
                    data <= response_data << response_shift;
                    tail_data <= response_data >> (128-response_shift);
                    tail_pending <= PHASE_ALIGN!=0;
                end
            end
        end
    end
    task automatic run_case(input bit stale, input bit corrupt=0, input bit drift=0);
        @(negedge clk); rst=1; enable=0; stale_second=stale; corrupt_lane=corrupt; mismatch_offset=drift;
        repeat (2) @(negedge clk);
        rst=0; enable=1;
        for (int n=0; n<300; n++) begin
            @(negedge clk);
            if (done) begin
                if (found==(stale || corrupt || drift) || gate0!=(stale || corrupt || drift ? 8'h00 : 8'h08) ||
                    gate1!=(stale || corrupt || drift ? 8'h00 : 8'h20) ||
                    change0!=(stale || SAME_DATA!=0 ? 8'h00 : 8'h08) ||
                    change1!=(stale || SAME_DATA!=0 ? 8'h00 : 8'h20) ||
                    col0_match0!=(corrupt ? 8'h00 : 8'h08) || col0_match1!=(corrupt ? 8'h00 : 8'h20) ||
                    col8_match0!=(stale || corrupt ? 8'h00 : 8'h08) ||
                    col8_match1!=(stale || corrupt ? 8'h00 : 8'h20) ||
                    write_count!=2 || read_count!=16 || pre_count!=1)
                    $fatal(1,"gate result mismatch: %h/%h found=%b",gate0,gate1,found);
                return;
            end
        end
        $fatal(1,"array gate scan timeout");
    endtask
    initial begin
        run_case(0);
        if (SAME_DATA==0) run_case(1);
        if (PHASE_SCAN!=0) run_case(0,1);
        if (PHASE_ALIGN!=0) run_case(0,0,1);
        $display("DDR array gate scan PASS: 8 candidates, distinct lane masks, stale columns");
        $finish;
    end
endmodule
