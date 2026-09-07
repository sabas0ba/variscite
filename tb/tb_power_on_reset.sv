`timescale 1ns/1ps
module tb_power_on_reset;
    reg clk = 0;
    wire rst;
    rv32ima_PowerOnReset dut (.i_clk(clk), .o_rst(rst));
    always #5 clk = ~clk;
    initial begin
        #1;
        if (rst !== 1'b1) $fatal(1, "reset must assert at configuration");
        for (integer cycle = 1; cycle <= 768; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (rst !== (cycle < 256))
                $fatal(1, "incorrect reset at cycle %0d: %b", cycle, rst);
        end
        $display("PASS: reset asserted for 256 clocks, then stays deasserted");
        $finish;
    end
endmodule
