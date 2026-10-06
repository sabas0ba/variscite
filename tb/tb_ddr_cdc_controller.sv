// Real CDC/controller connection; emulate only the trained PHY read output.
module tb_ddr_cdc_controller;
    integer cpu_half=19, mem_half=5;
    initial begin
        if ($value$plusargs("cpu_half=%d",cpu_half)) begin end
        if ($value$plusargs("mem_half=%d",mem_half)) begin end
        if (cpu_half<1 || mem_half<1) $fatal(1,"clock period");
    end
    reg cpu_clk=0, mem_clk=0, reset=1, valid=0, enable=0;
    integer cpu_ticks=0, mem_ticks=0;
    always #1 begin
        cpu_ticks++;
        mem_ticks++;
        if (cpu_ticks==cpu_half) begin cpu_ticks=0; cpu_clk=~cpu_clk; end
        if (mem_ticks==mem_half) begin mem_ticks=0; mem_clk=~mem_clk; end
    end
    reg [31:0] address=32'h80000000;
    reg [31:0] cpu_data=0;
    reg [3:0] cpu_strb=0;
    wire ready, error, req_valid, req_ready, rsp_valid, rsp_ready, rsp_error;
    wire [31:0] rdata;
    wire [26:0] req_addr;
    wire [127:0] req_data, rsp_data;
    wire [15:0] req_strb;
    wire cmd_valid;
    wire [2:0] cmd;
    wire [127:0] write_data;
    wire [15:0] write_mask;
    wire [3:0] dq_enable;
    reg [127:0] read_data=0;
    reg [1:0] read_valid=0;
    reg missing_lane=0;
    integer pending=0, accepts=0, responses=0, refreshes=0, rejected=0;
    localparam [127:0] PATTERN=128'hfedcba987654321089abcdef01234567;
    reg [127:0] memory=PATTERN, expected=PATTERN;
    rv32ima_DdrWordPort port (
        .i_cpu_clk(cpu_clk), .i_mem_clk(mem_clk), .i_reset(reset),
        .i_valid(valid), .i_addr(address), .i_wdata(cpu_data), .i_wstrb(cpu_strb),
        .o_ready(ready), .o_rdata(rdata), .o_error(error),
        .o_req_valid(req_valid), .i_req_ready(req_ready), .o_req_addr(req_addr),
        .o_req_wdata(req_data), .o_req_wstrb(req_strb),
        .i_rsp_valid(rsp_valid), .o_rsp_ready(rsp_ready),
        .i_rsp_data(rsp_data), .i_rsp_error(rsp_error)
    );
    rv32ima_DdrBurstController controller (
        .i_clk(mem_clk), .i_rst(reset), .i_enable(enable),
        .i_req_valid(req_valid), .o_req_ready(req_ready), .i_req_addr(req_addr),
        .i_req_data(req_data), .i_req_strb(req_strb),
        .o_rsp_valid(rsp_valid), .i_rsp_ready(rsp_ready),
        .o_rsp_data(rsp_data), .o_rsp_error(rsp_error),
        .i_read_data(read_data), .i_read_valid(read_valid),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(), .o_bank(),
        .o_read(), .o_odt(), .o_data(write_data), .o_mask(write_mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(), .o_dqs_pattern()
    );
    always @(posedge mem_clk) begin
        read_valid <= 0;
        if (reset) pending=0;
        else begin
            if (req_valid && req_ready) begin
                accepts++;
                if (req_addr !== {address[26:4],4'b0}) $fatal(1,"relative burst address");
            end
            if (rsp_valid && rsp_ready) responses++;
            if (dq_enable==4'hf)
                for (integer b=0; b<16; b++)
                    if (!write_mask[b]) memory[b*8+:8]=write_data[b*8+:8];
            if (pending != 0) begin
                pending--;
                if (pending==0) begin
                    read_valid <= missing_lane ? 1 : 3;
                    read_data <= memory;
                end
            end
            if (cmd_valid && cmd==3'b101) pending=5;
            if (cmd_valid && cmd==3'b001) refreshes++;
        end
    end
    task automatic read_word(input integer lane, input bit fail_read,
                             input [31:0] burst_base=32'h80000000);
        integer before_accepts, before_responses;
        before_accepts=accepts; before_responses=responses;
        @(negedge cpu_clk);
        address=burst_base+32'(lane*4); cpu_strb=0; missing_lane=fail_read; valid=1;
        do @(posedge cpu_clk); while (!ready);
        if (error !== fail_read || rdata !== (fail_read ? 32'b0 : expected[lane*32+:32]))
            $fatal(1,"CDC/controller response lane=%0d error=%b data=%h",lane,error,rdata);
        if (accepts!=before_accepts+1 || responses!=before_responses+1)
            $fatal(1,"request/response duplicated or lost");
        @(negedge cpu_clk); valid=0;
        repeat (3) @(negedge cpu_clk);
        if (ready || error) $fatal(1,"CPU response did not clear");
    endtask
    task automatic reject_word(input [31:0] bad_address, input [3:0] strobes);
        integer before_accepts, before_responses;
        before_accepts=accepts; before_responses=responses;
        @(negedge cpu_clk);
        address=bad_address; cpu_strb=strobes; valid=1;
        @(posedge cpu_clk);
        if (!ready || !error || rdata!==0) $fatal(1,"missing local address error %h",bad_address);
        @(negedge cpu_clk); valid=0;
        repeat (10) @(negedge mem_clk);
        if (req_valid || accepts!=before_accepts || responses!=before_responses)
            $fatal(1,"rejected address reached DDR %h",bad_address);
        @(negedge cpu_clk);
        if (ready || error) $fatal(1,"local error did not clear");
        rejected++;
    endtask
    task automatic write_word(input integer lane, input [3:0] strobes);
        integer before_accepts, before_responses;
        before_accepts=accepts; before_responses=responses;
        @(negedge cpu_clk);
        address=32'h80000000+32'(lane*4);
        cpu_data=32'h9137fac5 ^ (32'(strobes)*32'h01020408) ^ 32'(lane);
        cpu_strb=strobes; valid=1;
        do @(posedge cpu_clk); while (!ready);
        if (error || rdata!==0) $fatal(1,"write response");
        if (accepts!=before_accepts+1 || responses!=before_responses+1)
            $fatal(1,"write request/response duplicated or lost");
        for (integer b=0; b<4; b++)
            if (strobes[b]) expected[lane*32+b*8+:8]=cpu_data[b*8+:8];
        @(negedge cpu_clk); valid=0;
        repeat (3) @(negedge cpu_clk);
    endtask
    initial begin
        // Local rejection must also be suppressed during common reset.
        address=32'h88000000; valid=1;
        repeat (5) @(negedge cpu_clk);
        if (ready || error || req_valid) $fatal(1,"completion during reset");
        valid=0;
        reset=0;
        reject_word(32'h7ffffffc,0);
        reject_word(32'h88000000,4'hf);
        // A request before initialization completes must remain pending.
        fork
            read_word(0,0);
            begin
                repeat (100) @(negedge mem_clk);
                if (ready || accepts!=0) $fatal(1,"request accepted before enable");
                enable=1;
            end
        join
        for (integer lane=0; lane<4; lane++) begin
            read_word(lane,1);
            read_word(lane,0);
        end
        // Check both capacity boundaries and every high-bit alias of the same
        // physical address, with reads and writes. The PHY data model remains
        // one burst; address decoding is checked separately at acceptance.
        for (integer high_bits=0; high_bits<32; high_bits++)
            if (high_bits!=16) begin
                reject_word((32'(high_bits)<<27)|32'h10,0);
                reject_word((32'(high_bits)<<27)|32'h10,4'hf);
            end
        for (integer offset=1; offset<4; offset++) begin
            reject_word(32'h80000000+32'(offset),0);
            reject_word(32'h87fffffc+32'(offset),4'hf);
        end
        for (integer bit_index=4; bit_index<27; bit_index++)
            read_word(0,0,32'h80000000|(32'b1<<bit_index));
        read_word(3,0,32'h87fffff0);
        for (integer strobes=1; strobes<16; strobes++)
            for (integer lane=0; lane<4; lane++) begin
                write_word(lane,4'(strobes));
                // Check all lanes so an incorrect mask cannot silently damage
                // a neighboring CPU word in the same DDR burst.
                for (integer verify_lane=0; verify_lane<4; verify_lane++)
                    read_word(verify_lane,0);
            end
        repeat (1000) @(negedge mem_clk);
        if (refreshes<4) $fatal(1,"refresh stopped after requests");
        // Reset after backend acceptance cancels both mailboxes and the
        // controller transaction. No previous response may complete a new read.
        @(negedge cpu_clk); valid=1; missing_lane=1;
        wait(cmd_valid && cmd==3'b101);
        @(negedge mem_clk); reset=1; enable=0; valid=0;
        repeat (5) @(negedge cpu_clk);
        if (ready || error || req_valid || rsp_ready) $fatal(1,"reset did not cancel transaction");
        reset=0; enable=1;
        repeat (20) @(negedge cpu_clk);
        if (ready || error) $fatal(1,"stale response after reset");
        read_word(3,0);
        if (accepts!=335 || responses!=334 || rejected!=70) $fatal(1,"transaction totals");
        $display("[ddr-cdc-controller] PASS cpu_half=%0d mem_half=%0d requests=%0d responses=%0d rejected=%0d refreshes=%0d",
                 cpu_half,mem_half,accepts,responses,rejected,refreshes);
        $finish;
    end
    initial begin #1000000; $fatal(1,"integration watchdog"); end
endmodule
