module tb_ddr_mpr_delay_sweep;
    reg clk=0, rst=1, enable=0;
    reg [1:0] valid=0;
    reg [127:0] data=0;
    reg [127:0] pattern=0;
    wire cmd_valid, done, rloadn, rmove, rdir, delay_ready;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate;
    wire [5:0] sel;
    wire [1:0] hold_gate, found;
    wire [4:0] delay_target;
    wire [7:0] pass0, pass1;
    wire [5:0] phase0, phase1;
    reg reverse_enable=0;
    reg [4:0] reverse_target=0;
    wire reverse_loadn, reverse_move, reverse_dir, reverse_ready;
    reg reverse_done=0;
    integer cycles=0, reads=0, moves=0, delay_code=0, last_read=-100;
    integer reverse_code=0, reverse_moves=0;
    integer pending0=0, pending1=0;
    always #5 clk=~clk;

    rv32ima_DdrReadDelayStepper stepper (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_target(delay_target), .o_rloadn(rloadn), .o_rmove(rmove),
        .o_rdir(rdir), .o_ready(delay_ready)
    );
    rv32ima_DdrReadDelayStepper reverse_stepper (
        .i_clk(clk), .i_rst(rst), .i_enable(reverse_enable),
        .i_target(reverse_target), .o_rloadn(reverse_loadn),
        .o_rmove(reverse_move), .o_rdir(reverse_dir), .o_ready(reverse_ready)
    );
    rv32ima_DdrReadGateSweep #(.MPR_MODE(1), .DELAY_MODE(1)) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_burst(2'b00), .i_valid(valid), .i_data(data),
        .i_delay_ready(delay_ready),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(sel), .o_hold(hold_gate),
        .o_done(done), .o_found(found), .o_burst_seen(), .o_valid_seen(),
        .o_sample0(), .o_sample1(), .o_pattern0(), .o_pattern1(),
        .o_phase0(phase0), .o_phase1(phase1),
        .o_delay_target(delay_target), .o_pass_delay0(pass0),
        .o_pass_delay1(pass1), .o_align_pass0(), .o_align_pass1()
    );

    initial begin
        for (int beat=0; beat<8; beat++) begin
            pattern[16*beat]   = beat[0];
            pattern[16*beat+8] = beat[0];
        end
    end
    always @(negedge rmove) begin
        if (rloadn) begin
            delay_code = delay_code + (rdir ? -1 : 1);
            moves++;
        end
    end
    always @(negedge reverse_move) begin
        if (reverse_loadn) begin
            reverse_code += reverse_dir ? -1 : 1;
            reverse_moves++;
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        reverse_target=5;
        reverse_enable=1;
        wait (reverse_ready);
        @(negedge clk);
        reverse_target=2;
        @(negedge clk);
        wait (reverse_ready);
        @(negedge clk);
        if (reverse_code!=2 || reverse_moves!=8)
            $fatal(1,"reverse delay move failed: code=%0d moves=%0d", reverse_code, reverse_moves);
        reverse_done=1;
    end
    always @(posedge clk) begin
        cycles++;
        valid <= 0;
        data <= 0;
        if (!rloadn) delay_code=0;
        if (pending0>0) begin
            pending0--;
            if (pending0==0) begin valid[0] <= 1; data <= pattern; end
        end
        if (pending1>0) begin
            pending1--;
            if (pending1==0) begin valid[1] <= 1; data <= pattern; end
        end
        if (rst || !enable) begin
            pending0=0;
            pending1=0;
        end else begin
            if (cmd_valid && cmd==3'b101) begin
                if (!delay_ready || delay_code[4:0]!=delay_target || !rloadn || rmove)
                    $fatal(1,"READ before delay settled");
                reads++;
                last_read=cycles;
            end
            if (read_gate!=0) begin
                if (read_gate!=8'hff || hold_gate!=2'b00)
                    $fatal(1,"invalid READ gate");
                if ((delay_target==8 || delay_target==12) && cycles-last_read==4 && sel[2:0]==3'd2)
                    pending0=2;
                if ((delay_target==8 || delay_target==12) && cycles-last_read==4 && sel[5:3]==3'd5)
                    pending1=2;
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst=0;
        enable=1;
        wait (done);
        @(negedge clk);
        if (!reverse_done || reads!=1536 || moves!=28 || found!=2'b11 ||
            pass0!=8'h0c || pass1!=8'h0c || phase0!=6'd18 || phase1!=6'd21)
            $fatal(1,"delay scan mismatch: reads=%0d moves=%0d found=%b masks=%h/%h phases=%0d/%0d",
                reads, moves, found, pass0, pass1, phase0, phase1);
        $display("DDR MPR delay sweep PASS: 8 delays x 64 phases x 3 READs, two-lane eye masks");
        $finish;
    end
    initial begin
        repeat (30000) @(posedge clk);
        $fatal(1,"delay scan timeout");
    end
endmodule
