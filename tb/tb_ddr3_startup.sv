module tb_ddr3_startup;
    parameter bit REAL_TIMING = 0;
    localparam int RESET_WAIT = REAL_TIMING ? 19800 : 5;
    localparam int RELEASE_WAIT = REAL_TIMING ? 49500 : 9;
    localparam int XPR_WAIT = REAL_TIMING ? 40 : 3;
    localparam int ZQ_WAIT = REAL_TIMING ? 256 : 7;
    reg clk=0, rst=1, enable=0, ready=0;
    wire valid, reset_n, cke, done;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    always #5 clk=~clk;
    rv32ima_Ddr3Startup #(
        .RESET_CYCLES(RESET_WAIT), .RELEASE_CYCLES(RELEASE_WAIT),
        .XPR_CYCLES(XPR_WAIT), .MRD_CYCLES(2), .MOD_CYCLES(4),
        .ZQ_CYCLES(ZQ_WAIT), .MR0(14'h520), .MR1(14'h006), .MR2(14'h000)
    ) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable), .i_cmd_ready(ready),
        .o_cmd_valid(valid), .o_cmd(cmd), .o_bank(bank), .o_addr(addr),
        .o_reset_n(reset_n), .o_cke(cke), .o_done(done)
    );

    integer cycle=0, reset_count=0, release_count=0, cke_at=-1;
    integer commands=0, previous_at=-1, completed=0;
    reg held=0;
    reg [19:0] held_command;
    // Observe only the public command handshake and pin controls. No internal
    // state names or implementation counters are used by this scoreboard.
    always @(posedge clk) begin
        cycle=cycle+1;
        if (rst || !enable) begin
            reset_count=0; release_count=0; cke_at=-1;
            commands=0; previous_at=-1; held=0;
        end else begin
            if (held && (!valid || {cmd,bank,addr} !== held_command))
                $fatal(1,"command changed while PHY stalled");
            held=valid && !ready;
            held_command={cmd,bank,addr};
            if (!reset_n) begin
                reset_count=reset_count+1;
                if (cke || valid || done) $fatal(1,"activity during memory reset");
            end else begin
                if (reset_count < RESET_WAIT) $fatal(1,"RESET_n released early");
                if (!cke) release_count=release_count+1;
                else begin
                    if (release_count < RELEASE_WAIT) $fatal(1,"CKE asserted early");
                    if (cke_at < 0) cke_at=cycle;
                end
            end
            if (valid) begin
                if (!cke || cycle-cke_at < XPR_WAIT) $fatal(1,"MRS before tXPR");
                if (done) $fatal(1,"command issued after completion");
            end
            if (valid && ready) begin
                case (commands)
                    0: if ({cmd,bank,addr} !== {3'b000,3'd2,14'h000}) $fatal(1,"MR2");
                    1: if ({cmd,bank,addr} !== {3'b000,3'd3,14'h000}) $fatal(1,"MR3");
                    2: if ({cmd,bank,addr} !== {3'b000,3'd1,14'h006}) $fatal(1,"MR1");
                    3: if ({cmd,bank,addr} !== {3'b000,3'd0,14'h520}) $fatal(1,"MR0/DLL reset");
                    4: if ({cmd,bank,addr} !== {3'b110,3'd0,14'h400}) $fatal(1,"ZQCL");
                    default: $fatal(1,"extra initialization command");
                endcase
                if (commands > 0 && cycle-previous_at < (commands==4 ? 4 : 2))
                    $fatal(1,"tMRD/tMOD violation");
                previous_at=cycle;
                commands=commands+1;
            end
            if (done && (commands!=5 || cycle-previous_at < ZQ_WAIT))
                $fatal(1,"ready before all MRS/ZQ and settling");
        end
    end

    task automatic restart;
        @(negedge clk); rst=1; enable=0; ready=0;
        repeat (3) @(negedge clk);
        rst=0; enable=1;
    endtask
    task automatic finish_sequence;
        integer timeout;
        timeout=0;
        while (!done) begin
            @(negedge clk);
            // Regular multi-cycle backpressure exercises retained commands.
            ready=(timeout%7 >= 3);
            timeout=timeout+1;
            if (timeout > RESET_WAIT+RELEASE_WAIT+XPR_WAIT+ZQ_WAIT+120)
                $fatal(1,"initialization watchdog");
        end
        completed=completed+1;
        repeat (10) @(negedge clk);
        if (!done || valid) $fatal(1,"completion is not retained");
    endtask
    initial begin
        restart();
        finish_sequence();
        // PHY lock loss must suppress a completed controller and restart.
        enable=0;
        #1;
        if (done || valid || cke || reset_n) $fatal(1,"PHY loss not gated");
        repeat (3) @(negedge clk);
        enable=1;
        finish_sequence();
        // Reset each of the five commands while stalled. The next successful
        // sequence must start at MR2, never continue the interrupted command.
        for (integer target=0; target<5; target=target+1) begin
            restart();
            while (commands < target) begin
                @(negedge clk); ready=1;
            end
            ready=0;
            wait(valid);
            repeat (4) @(negedge clk);
            restart();
            finish_sequence();
        end
        // Also interrupt the power-up and post-ZQ waits.
        restart();
        repeat (2) @(negedge clk);
        restart();
        finish_sequence();
        restart();
        ready=1;
        wait(commands==5);
        @(negedge clk);
        restart();
        finish_sequence();
        $display("[ddr3-startup] PASS real_timing=%0d completed=%0d",REAL_TIMING,completed);
        $finish;
    end
    initial begin #20000000; $fatal(1,"global watchdog"); end
endmodule
