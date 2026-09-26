module tb_ddr_mpr_align_sweep;
    reg clk=0, rst=1, enable=0;
    reg [1:0] valid=0;
    reg [127:0] data=0;
    reg [127:0] pattern0=0, pattern1=0;
    wire cmd_valid, done, rloadn, rmove, rdir, delay_ready;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate;
    wire [5:0] sel;
    wire [1:0] hold_gate, found;
    wire [4:0] delay_target;
    wire [7:0] pass0, pass1;
    wire [2:0] align0, align1;
    integer cycles=0, reads=0, moves=0, delay_code=0, last_read=-100;
    integer age0=-1, age1=-1, offset0=0, offset1=0;
    always #5 clk=~clk;

    rv32ima_DdrReadDelayStepper stepper (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_target(delay_target), .o_rloadn(rloadn), .o_rmove(rmove),
        .o_rdir(rdir), .o_ready(delay_ready)
    );
    rv32ima_DdrReadGateSweep #(.MPR_MODE(1), .DELAY_MODE(1), .ALIGN_MODE(1)) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_burst(2'b00), .i_valid(valid), .i_data(data),
        .i_delay_ready(delay_ready),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(sel), .o_hold(hold_gate),
        .o_done(done), .o_found(found), .o_burst_seen(), .o_valid_seen(),
        .o_sample0(), .o_sample1(), .o_pattern0(), .o_pattern1(),
        .o_phase0(), .o_phase1(),
        .o_delay_target(delay_target), .o_pass_delay0(pass0),
        .o_pass_delay1(pass1), .o_align_pass0(align0), .o_align_pass1(align1)
    );
    initial begin
        for (int beat=0; beat<8; beat++) begin
            pattern0[16*beat] = beat[0];
            pattern1[16*beat+8] = beat[0];
        end
    end
    always @(negedge rmove) begin
        if (rloadn) begin
            delay_code += rdir ? -1 : 1;
            moves++;
        end
    end
    always @(posedge clk) begin
        cycles++;
        valid <= 0;
        data <= 0;
        if (!rloadn) delay_code=0;
        if (age0>=0) begin
            age0++;
            if (age0==3) valid[0] <= 1;
            if (age0==3+offset0) data <= data | pattern0;
            if (age0==5) age0=-1;
        end
        if (age1>=0) begin
            age1++;
            if (age1==3) valid[1] <= 1;
            if (age1==3+offset1) data <= data | pattern1;
            if (age1==5) age1=-1;
        end
        if (rst || !enable) begin
            age0=-1;
            age1=-1;
        end else begin
            if (cmd_valid && cmd==3'b101) begin
                if (!delay_ready || delay_code[4:0]!=delay_target || !rloadn || rmove)
                    $fatal(1,"READ before delay settled");
                reads++;
                last_read=cycles;
            end
            if (read_gate!=0) begin
                if (read_gate!=8'hff || hold_gate!=0)
                    $fatal(1,"invalid READ gate");
                if (cycles-last_read==4 && sel[2:0]==3'd2) begin
                    if (delay_target==8 || delay_target==12 ||
                        (delay_target==0 && reads%3==1 && sel[5:3]==3'd3)) begin
                        age0=0;
                        offset0=(delay_target==12) ? 1 : -1;
                    end
                end
                if (cycles-last_read==4 && sel[5:3]==3'd5 &&
                    (delay_target==8 || delay_target==12)) begin
                    age1=0;
                    offset1=(delay_target==8) ? 0 : 1;
                end
            end
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        rst=0;
        enable=1;
        wait (done);
        @(negedge clk);
        if (reads!=1536 || moves!=28 || found!=2'b11 ||
            align0!=3'b101 || align1!=3'b110 ||
            pass0!=8'h0c || pass1!=8'h0c)
            $fatal(1,"alignment mismatch: reads=%0d moves=%0d found=%b align=%b/%b delays=%h/%h",
                reads, moves, found, align0, align1, pass0, pass1);
        $display("DDR MPR alignment PASS: three READs per candidate and independent lane offsets");
        $finish;
    end
    initial begin
        repeat (30000) @(posedge clk);
        $fatal(1,"alignment scan timeout");
    end
endmodule
