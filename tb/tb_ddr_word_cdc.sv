module tb_ddr_word_cdc;
    reg cpu_clk=0, mem_clk=0, reset=1, mem_run=1;
    integer cpu_half=5, mem_half=3, cpu_ticks=0, mem_ticks=0;
    reg valid=0, req_ready=0, rsp_valid=0;
    reg [31:0] addr=0, wdata=0;
    reg [3:0] wstrb=0;
    reg [127:0] rsp_data=0;
    wire ready, req_valid;
    wire [31:0] rdata, req_addr;
    wire [127:0] req_wdata;
    wire [15:0] req_wstrb;
    reg [31:0] expected [0:255];
    reg [127:0] memory [0:63];
    integer accepted=0, transactions=0;
    initial begin
        if ($value$plusargs("cpu_half=%d",cpu_half)) begin end
        if ($value$plusargs("mem_half=%d",mem_half)) begin end
        if (cpu_half<1 || mem_half<1) $fatal(1,"clock period");
    end
    always #1 begin
        cpu_ticks=cpu_ticks+1;
        if (cpu_ticks==cpu_half) begin cpu_ticks=0; cpu_clk=~cpu_clk; end
        if (mem_run) begin
            mem_ticks=mem_ticks+1;
            if (mem_ticks==mem_half) begin mem_ticks=0; mem_clk=~mem_clk; end
        end
    end
    rv32ima_DdrWordCdc dut (
        .i_cpu_clk(cpu_clk), .i_mem_clk(mem_clk), .i_reset(reset),
        .i_valid(valid), .i_addr(addr), .i_wdata(wdata), .i_wstrb(wstrb),
        .o_ready(ready), .o_rdata(rdata), .o_req_valid(req_valid),
        .i_req_ready(req_ready), .o_req_addr(req_addr),
        .o_req_wdata(req_wdata), .o_req_wstrb(req_wstrb),
        .i_rsp_valid(rsp_valid), .i_rsp_data(rsp_data)
    );
    always @(posedge mem_clk)
        if (!reset && req_valid && req_ready) accepted=accepted+1;

    task automatic transfer(input integer word_index, input [31:0] data,
                            input [3:0] mask, input integer delay_cycles);
        reg [175:0] saved;
        reg [31:0] before_value;
        integer before_accepted;
        before_value=expected[word_index];
        before_accepted=accepted;
        @(negedge cpu_clk);
        addr=32'h80000000+32'(word_index*4); wdata=data; wstrb=mask; valid=1;
        fork
            begin
                do @(posedge cpu_clk); while (!ready);
                if (rdata !== before_value) $fatal(1,"read mismatch word=%0d got=%h expected=%h",word_index,rdata,before_value);
                @(negedge cpu_clk); valid=0;
            end
            begin
                wait(req_valid);
                @(negedge mem_clk);
                saved={req_addr,req_wdata,req_wstrb};
                repeat (5) begin
                    @(negedge mem_clk);
                    if (!req_valid || {req_addr,req_wdata,req_wstrb} !== saved)
                        $fatal(1,"backend request not retained");
                end
                if (req_addr !== (addr & 32'hfffffff0)) $fatal(1,"burst alignment");
                if (req_wstrb !== (16'(mask) << ((word_index%4)*4))) $fatal(1,"byte strobes");
                if (req_wdata !== (128'(data) << ((word_index%4)*32))) $fatal(1,"word placement");
                rsp_data=memory[word_index/4];
                req_ready=1;
                rsp_valid=(delay_cycles==0);
                @(posedge mem_clk);
                for (integer b=0; b<16; b=b+1)
                    if (req_wstrb[b]) memory[word_index/4][b*8+:8]=req_wdata[b*8+:8];
                @(negedge mem_clk); req_ready=0;
                if (delay_cycles!=0) begin
                    repeat (delay_cycles) @(negedge mem_clk);
                    rsp_valid=1;
                    @(negedge mem_clk);
                end
                rsp_valid=0;
            end
        join
        for (integer b=0; b<4; b=b+1)
            if (mask[b]) expected[word_index][b*8+:8]=data[b*8+:8];
        transactions=transactions+1;
        if (accepted!=before_accepted+1) $fatal(1,"request duplicated or lost");
    endtask
    initial begin
        for (integer w=0; w<256; w=w+1) begin
            expected[w]=32'h9e3779b9 ^ (32'(w)*32'h1020301);
            memory[w/4][(w%4)*32+:32]=expected[w];
        end
        repeat (5) @(negedge cpu_clk);
        reset=0;
        for (integer mask=0; mask<16; mask=mask+1)
            for (integer word_lane=0; word_lane<4; word_lane=word_lane+1) begin
                transfer(mask*4+word_lane,32'h12345678 ^ 32'(mask*999+word_lane),4'(mask),mask%9);
                transfer(mask*4+word_lane,0,0,word_lane);
            end
        // Exercise the last burst in the model as well as address bit changes.
        transfer(255,32'hcafebabe,4'hf,31);
        transfer(255,0,0,0);
        // Cancel an accepted read while the destination clock is stopped.
        @(negedge cpu_clk); valid=1; addr=32'h80000000; wstrb=0;
        wait(req_valid);
        @(negedge mem_clk); req_ready=1;
        @(negedge mem_clk); req_ready=0; mem_run=0;
        @(negedge cpu_clk); reset=1; valid=0;
        #1;
        if (ready || req_valid) $fatal(1,"reset needs stopped memory clock");
        repeat (4) @(negedge cpu_clk);
        mem_run=1;
        repeat (4) @(negedge cpu_clk);
        reset=0;
        repeat (10) begin
            @(negedge cpu_clk);
            if (ready || req_valid) $fatal(1,"stale response after reset");
        end
        transfer(0,0,0,17);
        transfer(3,32'h76543210,4'ha,0);
        transfer(3,0,0,0);
        $display("[ddr-word-cdc] PASS cpu_half=%0d mem_half=%0d transactions=%0d",cpu_half,mem_half,transactions);
        $finish;
    end
    initial begin #5000000; $fatal(1,"CDC watchdog"); end
endmodule
