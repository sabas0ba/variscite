module tb_ddr_mpr_sweep;
    reg clk=0, rst=1, enable=0, respond=1;
    reg [1:0] valid=0;
    reg [127:0] data=0;
    reg [127:0] pattern=0;
    wire cmd_valid, done;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate;
    wire [5:0] sel;
    wire [1:0] hold_gate, found, valid_seen;
    wire [5:0] phase0, phase1;
    wire [7:0] sample0, sample1;
    wire [7:0] observed0, observed1;
    integer cycle=0, last_read=-100, mrs_on=-100, reads=0, mrs_count=0;
    integer pending0=0, pending1=0;
    always #5 clk=~clk;
    rv32ima_DdrReadGateSweep #(.MPR_MODE(1)) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable), .i_burst(2'b00),
        .i_valid(valid), .i_data(data),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(sel), .o_hold(hold_gate),
        .o_done(done), .o_found(found), .o_burst_seen(), .o_valid_seen(valid_seen),
        .o_sample0(sample0), .o_sample1(sample1),
        .o_pattern0(observed0), .o_pattern1(observed1),
        .o_phase0(phase0), .o_phase1(phase1)
    );

    initial begin
        for (int beat=0; beat<8; beat++) begin
            pattern[16*beat]   = beat[0];
            pattern[16*beat+8] = beat[0];
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        valid <= 0;
        data <= 0;
        if (pending0>0) begin
            pending0=pending0-1;
            if (pending0==0) begin valid[0] <= 1; data <= pattern; end
        end
        if (pending1>0) begin
            pending1=pending1-1;
            if (pending1==0) begin valid[1] <= 1; data <= pattern; end
        end
        if (rst || !enable) begin
            pending0=0; pending1=0;
        end else begin
            if (cmd_valid) begin
                case (cmd)
                    3'b000: begin
                        if (bank!=3 || (mrs_count==0 && addr!=14'h004) ||
                            (mrs_count==1 && addr!=0) || mrs_count>1)
                            $fatal(1,"invalid MR3 sequence");
                        if (mrs_count==0) mrs_on=cycle;
                        else if (reads==0 || cycle-last_read<12)
                            $fatal(1,"MPR exit too early");
                        mrs_count=mrs_count+1;
                    end
                    3'b101: begin
                        if (bank!=0 || addr!=14'h1000 || mrs_count!=1 ||
                            cycle-mrs_on<12 || (reads!=0 && cycle-last_read<12))
                            $fatal(1,"invalid MPR READ timing");
                        reads=reads+1;
                        last_read=cycle;
                    end
                    default: $fatal(1,"unexpected command in MPR mode");
                endcase
            end
            if (read_gate[3:0]!=0) begin
                if (read_gate[3:0]!=4'hf || cmd_valid || hold_gate[0])
                    $fatal(1,"lane 0 gate shape");
                if (respond && sel[2:0]==3'd2 && cycle-last_read==2) pending0=2;
            end
            if (read_gate[7:4]!=0) begin
                if (read_gate[7:4]!=4'hf || cmd_valid || hold_gate[1])
                    $fatal(1,"lane 1 gate shape");
                if (respond && sel[5:3]==3'd3 && cycle-last_read==4) pending1=2;
            end
            if (done && (cmd_valid || read_gate!=0 || hold_gate!=0))
                $fatal(1,"activity after completion");
        end
    end

    task automatic start_case(input bit with_response);
        @(negedge clk); rst=1; enable=0; respond=with_response;
        @(negedge clk); mrs_count=0; reads=0; last_read=-100; mrs_on=-100;
        rst=0; enable=1;
    endtask
    task automatic await_done(input integer max_cycles);
        for (int n=0;n<max_cycles;n++) begin
            @(negedge clk);
            if (done) return;
        end
        $fatal(1,"MPR sweep timeout");
    endtask
    initial begin
        start_case(1);
        await_done(900);
        if (found!==2'b11 || phase0!==6'd2 || phase1!==6'd19 ||
            mrs_count!=2 || reads<20 || reads>32 || sample0!=8'h01 || sample1!=8'h01 ||
            observed0!=8'haa || observed1!=8'haa)
            $fatal(1,"MPR lane phases/commands wrong");

        pattern = 0;
        start_case(1);
        await_done(900);
        if (found!==2'b00 || valid_seen!==2'b11 || mrs_count!=2 || reads!=64 ||
            observed0!=0 || observed1!=0)
            $fatal(1,"invalid MPR data was accepted");

        start_case(0);
        await_done(900);
        if (found!==2'b00 || mrs_count!=2 || reads!=64)
            $fatal(1,"MPR timeout case wrong");
        $display("DDR MPR sweep PASS: both lane patterns, MR3 timing, timeout");
        $finish;
    end
    initial begin
        #30000;
        $fatal(1,"global timeout");
    end
endmodule
