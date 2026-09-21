module tb_ddr_read_gate_sweep;
    reg clk=0, rst=1, enable=0, respond=1;
    reg [1:0] burst=0;
    wire cmd_valid, done;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate;
    wire [5:0] sel;
    wire [1:0] hold_gate, found;
    wire [4:0] phase0, phase1;
    integer cycle=0, last_read=-100, reads=0, acts=0, pres=0;
    integer pending0=0, pending1=0;
    always #5 clk=~clk;
    rv32ima_DdrReadGateSweep dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable), .i_burst(burst),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_sel(sel), .o_hold(hold_gate),
        .o_done(done), .o_found(found), .o_phase0(phase0), .o_phase1(phase1)
    );

    // The mock DRAM returns a lane-specific DQS burst only at the chosen gate
    // position and phase. It does not depend on the DUT's internal state.
    always @(posedge clk) begin
        cycle=cycle+1;
        burst <= 0;
        if (pending0>0) begin
            pending0=pending0-1;
            if (pending0==0) burst[0] <= 1;
        end
        if (pending1>0) begin
            pending1=pending1-1;
            if (pending1==0) burst[1] <= 1;
        end
        if (rst || !enable) begin
            pending0=0; pending1=0;
        end else begin
            if (cmd_valid) begin
                if (bank!=0) $fatal(1,"bank must be zero");
                case (cmd)
                    3'b011: begin
                        if (addr!=0 || acts!=0 || reads!=0) $fatal(1,"ACT order/address");
                        acts=acts+1;
                    end
                    3'b101: begin
                        if (acts!=1 || pres!=0 || addr!=0) $fatal(1,"READ order/address");
                        if (reads!=0 && cycle-last_read<12) $fatal(1,"READs too close");
                        reads=reads+1;
                        last_read=cycle;
                    end
                    3'b010: begin
                        if (acts!=1 || reads==0 || pres!=0 || addr!==14'h400)
                            $fatal(1,"PRE order/address");
                        pres=pres+1;
                    end
                    default: $fatal(1,"unexpected DDR command");
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
        @(negedge clk); acts=0; pres=0; reads=0; last_read=-100;
        rst=0; enable=1;
    endtask
    task automatic await_done(input integer max_cycles);
        for (int n=0;n<max_cycles;n++) begin
            @(negedge clk);
            if (done) return;
        end
        $fatal(1,"sweep timeout");
    endtask

    initial begin
        start_case(1);
        await_done(500);
        if (found!==2'b11 || phase0!==5'd2 || phase1!==5'd19)
            $fatal(1,"lane phases wrong: found=%b phase0=%d phase1=%d",found,phase0,phase1);
        if (acts!=1 || pres!=1 || reads<20 || reads>32)
            $fatal(1,"unexpected command counts on success");

        start_case(0);
        await_done(500);
        if (found!==2'b00 || acts!=1 || pres!=1 || reads!=32)
            $fatal(1,"no-DQS case did not exhaust the search");

        start_case(1);
        repeat (60) @(negedge clk);
        enable=0;
        @(negedge clk);
        if (done || found!=0 || cmd_valid) $fatal(1,"enable loss failed to reset search");
        rst=1;
        @(negedge clk);
        $display("DDR READ gate sweep PASS: two independent lane phases, 32-position timeout, enable loss");
        $finish;
    end
    initial begin
        #30000;
        $fatal(1,"global timeout");
    end
endmodule
