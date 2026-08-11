// Multi-source PLIC testbench.
//
// This one lives outside src/tests.veryl on purpose. `veryl test` hands the
// whole design to Verilator alongside the testbench, so every design module
// that nothing instantiates becomes an additional top. With several tops
// rv32ima_Plic is specialised only once, and a testbench that overrides
// SRC_COUNT silently gets the platform's value of 1 instead. Building this
// standalone with an explicit --top-module, and only the files it needs,
// keeps the override honest. Run it with `make plic-multi-test`.
//
// The platform instantiates one PLIC source, so priority ordering between
// sources is only reachable in a wider configuration. Exercise it here.
module tb_plic_multi;
    localparam int N = 4;

    logic        clk = 0;
    logic        rst = 1;
    logic        sel = 0;
    logic [21:0] addr = 0;
    logic [3:0]  wstrb = 0;
    logic [31:0] wdata = 0;
    logic [31:0] rdata;
    logic [N-1:0] src = 0;
    logic        irq;

    rv32ima_Plic #(.SRC_COUNT (N)) dut (
        .i_clk   (clk),
        .i_rst   (rst),
        .i_sel   (sel),
        .i_addr  (addr),
        .i_wstrb (wstrb),
        .i_wdata (wdata),
        .o_rdata (rdata),
        .i_src   (src),
        .o_irq   (irq)
    );

    always #5 clk = ~clk;

    task automatic bus_write(input logic [21:0] a, input logic [31:0] d);
        @(negedge clk);
        sel = 1; addr = a; wstrb = 4'hf; wdata = d;
        @(posedge clk);
        @(negedge clk);
        sel = 0; wstrb = 4'h0;
    endtask

    task automatic bus_read(input logic [21:0] a, output logic [31:0] d);
        @(negedge clk);
        sel = 1; addr = a; wstrb = 4'h0;
        #1 d = rdata;
        @(posedge clk);
        @(negedge clk);
        sel = 0;
    endtask

    logic [31:0] v;

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // All four sources exist and can be enabled.
        bus_write(22'h002000, 32'hffff_ffff);
        bus_read(22'h002000, v);
        assert (v == 32'h1e) else $fatal(1, "enable=%h, expected sources 1..4", v);

        // Sources 2 and 3 share a priority; 4 is higher, 1 is lower.
        bus_write(22'h000004, 32'd1);
        bus_write(22'h000008, 32'd3);
        bus_write(22'h00000c, 32'd3);
        bus_write(22'h000010, 32'd7);

        // Equal priority: the lowest source number wins the claim.
        src = 4'b0110; // sources 2 and 3
        #1;
        assert (irq == 1'b1) else $fatal(1, "irq not raised");
        bus_read(22'h001000, v);
        assert (v == 32'h0c) else $fatal(1, "pending=%h", v);
        bus_read(22'h200004, v);
        assert (v == 32'd2) else $fatal(1, "claim=%0d, expected the lower id 2", v);

        // Source 3 is still pending and interrupts on its own.
        assert (irq == 1'b1) else $fatal(1, "source 3 lost while 2 was claimed");
        bus_read(22'h200004, v);
        assert (v == 32'd3) else $fatal(1, "claim=%0d, expected 3", v);
        assert (irq == 1'b0) else $fatal(1, "irq with both sources claimed");

        // A higher-priority source raised later wins the next claim.
        src = 4'b1111;
        #1;
        bus_read(22'h200004, v);
        assert (v == 32'd4) else $fatal(1, "claim=%0d, expected the highest priority 4", v);
        bus_read(22'h200004, v);
        assert (v == 32'd1) else $fatal(1, "claim=%0d, expected the last source 1", v);

        // Completing one source does not disturb the others' claims.
        bus_write(22'h200004, 32'd3);
        bus_read(22'h001000, v);
        assert (v == 32'h08) else $fatal(1, "pending=%h, only source 3 should return", v);

        // The threshold filters by priority, not by source number.
        bus_write(22'h200000, 32'd3);
        assert (irq == 1'b0) else $fatal(1, "priority 3 passed a threshold of 3");
        bus_write(22'h200000, 32'd2);
        assert (irq == 1'b1) else $fatal(1, "priority 3 blocked by a threshold of 2");

        $display("tb_plic_multi OK");
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule
