// Reset release waits for two edges in each domain, including a stopped clock.
module tb_lcd_reset;
    reg cpu_clk=0, pixel_clk=0, reset_request=0, pixel_running=1;
    wire cpu_ready, pixel_ready;
    rv32ima_TangLcdReset dut (
        .i_cpu_clk(cpu_clk), .i_pixel_clk(pixel_clk), .i_reset(reset_request),
        .o_cpu_ready(cpu_ready), .o_pixel_ready(pixel_ready)
    );
    always #5 cpu_clk=~cpu_clk;
    always #7 if(pixel_running) pixel_clk=~pixel_clk;
    initial begin #10000; $fatal(1,"reset watchdog"); end
    task automatic release_check;
        fork
            begin
                @(posedge cpu_clk); #1;
                if(cpu_ready) $fatal(1,"CPU reset released after one edge");
                @(posedge cpu_clk); #1;
                if(!cpu_ready) $fatal(1,"CPU reset not released after two edges");
            end
            begin
                @(posedge pixel_clk); #1;
                if(pixel_ready) $fatal(1,"pixel reset released after one edge");
                @(posedge pixel_clk); #1;
                if(!pixel_ready) $fatal(1,"pixel reset not released after two edges");
            end
        join
    endtask
    initial begin
        #2; reset_request=1;
        #1; if(cpu_ready || pixel_ready) $fatal(1,"asynchronous assertion");
        #5; reset_request=0;
        release_check();
        @(negedge pixel_clk); pixel_running=0;
        #2; reset_request=1;
        #1; if(cpu_ready || pixel_ready) $fatal(1,"assertion with stopped pixel clock");
        #5; reset_request=0;
        repeat(5) @(negedge cpu_clk);
        if(!cpu_ready || pixel_ready) $fatal(1,"stopped domain released reset");
        pixel_running=1;
        @(posedge pixel_clk); #1;
        if(pixel_ready) $fatal(1,"restart released after one edge");
        @(posedge pixel_clk); #1;
        if(!pixel_ready) $fatal(1,"restart failed");
        for(integer phase=1;phase<=9;phase=phase+1) begin
            repeat(phase) #1;
            reset_request=1;
            #1; if(cpu_ready || pixel_ready) $fatal(1,"short reset pulse missed");
            // Deassert between edges to avoid a testbench scheduling race.
            #0.5; reset_request=0;
            release_check();
        end
        $display("PASS: LCD reset assertion, two-edge release, stopped clock and repeated lock loss");
        $finish;
    end
endmodule
