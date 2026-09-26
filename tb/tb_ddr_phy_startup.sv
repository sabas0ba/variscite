module tb_ddr_phy_startup;
    reg clk=0, rst=1, pll_locked=0, dll_locked=0;
    wire freeze_clock, stop_clock, div_reset, phy_reset, hold_dqs, update_n, ready;
    wire [6:0] controls={freeze_clock,stop_clock,div_reset,phy_reset,hold_dqs,update_n,ready};
    localparam [6:0] SEQUENCE [0:10]='{7'h0a,7'h4a,7'h6a,7'h7a,7'h62,7'h42,7'h02,7'h06,7'h04,7'h06,7'h03};
    always #5 clk=~clk;
    time reset_release;
    always @(negedge phy_reset) begin
        reset_release=$time;
        #1;
        if (!stop_clock) $fatal(1,"PHY reset released with clocks running");
    end
    always @(negedge div_reset) begin
        if (!rst) begin
            #1;
            if (!stop_clock && pll_locked) $fatal(1,"divider reset released with clocks running");
        end
    end
    always @(negedge stop_clock) begin
        #1;
        if (!phy_reset && $time-reset_release<80)
            $fatal(1,"clock resumed before reset recovery interval");
    end
    rv32ima_DdrPhyStartup dut (
        .i_clk(clk), .i_rst(rst), .i_pll_locked(pll_locked), .i_dll_locked(dll_locked),
        .o_freeze(freeze_clock), .o_stop(stop_clock), .o_div_reset(div_reset),
        .o_phy_reset(phy_reset), .o_hold(hold_dqs), .o_update_n(update_n), .o_ready(ready)
    );
    task automatic check(input integer stage);
        #1;
        if (controls!==SEQUENCE[stage])
            $fatal(1,"stage %0d expected %h got %h",stage,SEQUENCE[stage],controls);
    endtask
    task automatic run_sequence;
        pll_locked=1;
        dll_locked=1;
        for (int stage=0; stage<10; stage++) begin
            repeat (8) begin
                check(stage);
                @(negedge clk);
            end
        end
        check(10);
        repeat (12) begin @(negedge clk); check(10); end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        rst=0;
        repeat (10) begin @(negedge clk); check(0); end
        pll_locked=1;
        repeat (10) begin @(negedge clk); check(0); end
        // Interrupt while the DDR clocks are stopped; reference-domain recovery must work.
        dll_locked=1;
        repeat (16) @(negedge clk);
        check(2);
        pll_locked=0;
        @(negedge clk);
        check(0);
        run_sequence();
        dll_locked=0;
        #1;
        if (ready) $fatal(1,"ready remained high on DLL loss");
        @(negedge clk);
        check(0);
        repeat (5) @(negedge clk);
        run_sequence();
        rst=1;
        @(negedge clk);
        check(0);
        $display("DDR PHY startup PASS: lock qualification, ordered freeze/stop/reset/update, durations, PLL loss while stopped, DLL loss and restart");
        $finish;
    end
    initial begin
        repeat (300) @(posedge clk);
        $fatal(1,"PHY startup timeout");
    end
endmodule
