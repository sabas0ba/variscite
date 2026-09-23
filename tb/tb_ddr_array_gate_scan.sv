module tb_ddr_array_gate_scan;
    localparam [127:0] DATA_A = 128'ha55a_5aa5_c33c_3cc3_9669_6996_f00f_0ff0;
    localparam [127:0] DATA_B = ~DATA_A;
    reg clk=0, rst=1, enable=0;
    reg [1:0] valid=0, burst=0;
    reg [127:0] data=0;
    wire cmd_valid, done, found;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, gate0, gate1;
    integer cycle=0, read_cycle=-100, read_count=0, write_count=0, pre_count=0;
    always #5 clk=~clk;

    rv32ima_DdrArrayProbe #(.GATE_SCAN(1)) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_burst(burst), .i_valid(valid), .i_data(data),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(), .o_hold(), .o_odt(),
        .o_data(), .o_mask(), .o_dq_enable(), .o_dqs_enable(),
        .o_dqs_pattern(), .o_done(done), .o_found(found),
        .o_burst_seen(), .o_valid_seen(), .o_match0(), .o_match1(),
        .o_pass_gate0(gate0), .o_pass_gate1(gate1),
        .o_first_raw0(), .o_first_raw1(), .o_raw0(), .o_raw1()
    );

    always @(posedge clk) begin
        cycle++;
        valid <= 0;
        burst <= 0;
        data <= 0;
        if (rst || !enable) begin
            read_count=0;
            write_count=0;
            pre_count=0;
            read_cycle=-100;
        end else begin
            if (cmd_valid) begin
                if (bank!=0) $fatal(1,"unexpected bank");
                case (cmd)
                    3'b011: if (write_count!=0 || read_count!=0 || addr!=0)
                        $fatal(1,"ACT sequence");
                    3'b100: begin
                        if (write_count>=2 || addr!=(write_count==0 ? 0 : 8))
                            $fatal(1,"WRITE sequence");
                        write_count++;
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
            if (read_gate!=0) begin
                if (read_gate!=8'hff || read_count==0 ||
                    cycle-read_cycle!=((read_count-1)/2)+2)
                    $fatal(1,"gate schedule at read %0d",read_count);
                // Only DQ0 at candidate 3 and DQ8 at candidate 5 are valid.
                if ((read_count-1)/2==3) begin
                    valid <= 2'b01;
                    burst <= 2'b01;
                    data <= read_count%2==1 ? DATA_A : DATA_B;
                end
                if ((read_count-1)/2==5) begin
                    valid <= 2'b10;
                    burst <= 2'b10;
                    data <= read_count%2==1 ? DATA_A : DATA_B;
                end
            end
        end
    end
    initial begin
        repeat (2) @(negedge clk);
        rst=0; enable=1;
        for (int n=0; n<300; n++) begin
            @(negedge clk);
            if (done) begin
                if (!found || gate0!=8'h08 || gate1!=8'h20 ||
                    write_count!=2 || read_count!=16 || pre_count!=1)
                    $fatal(1,"gate result mismatch: %h/%h found=%b",gate0,gate1,found);
                $display("DDR array gate scan PASS: 8 candidates, distinct lane masks");
                $finish;
                break;
            end
        end
        if (!done) $fatal(1,"array gate scan timeout");
    end
endmodule
