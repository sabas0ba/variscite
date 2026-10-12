// Independent byte-addressed backend with request/response stalls.
module tb_ddr_burst_read_cache;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic req_valid=0, rsp_ready=0;
    logic [26:0] req_addr=0;
    logic [127:0] req_data=0;
    logic [15:0] req_strb=0;
    wire req_ready, rsp_valid, rsp_error;
    wire [127:0] rsp_data;
    wire mem_valid, mem_rsp_ready;
    wire [26:0] mem_addr;
    wire [127:0] mem_data;
    wire [15:0] mem_strb;
    logic mem_ready=0, mem_rsp_valid=0, mem_rsp_error=0;
    logic [127:0] mem_rsp_data=0;
    byte unsigned memory[4096];
    int transfers=0, cycles=0, delay_left=0;
    bit pending=0, inject_error=0;
    logic [127:0] saved_response;
    bit saved_error;
    rv32ima_DdrBurstReadCache dut (
        .i_clk(clk), .i_rst(rst), .i_req_valid(req_valid), .o_req_ready(req_ready),
        .i_req_addr(req_addr), .i_req_data(req_data), .i_req_strb(req_strb),
        .o_rsp_valid(rsp_valid), .i_rsp_ready(rsp_ready), .o_rsp_data(rsp_data), .o_rsp_error(rsp_error),
        .o_mem_valid(mem_valid), .i_mem_ready(mem_ready), .o_mem_addr(mem_addr),
        .o_mem_data(mem_data), .o_mem_strb(mem_strb), .i_mem_rsp_valid(mem_rsp_valid),
        .o_mem_rsp_ready(mem_rsp_ready), .i_mem_rsp_data(mem_rsp_data), .i_mem_rsp_error(mem_rsp_error)
    );
    always @(negedge clk) mem_ready = !rst && !pending && !mem_rsp_valid && cycles%4==0;
    always @(posedge clk) begin
        cycles <= cycles+1;
        if (rst) begin
            pending<=0;
            mem_rsp_valid<=0;
        end else begin
            if (mem_rsp_valid && mem_rsp_ready) mem_rsp_valid<=0;
            if (pending) begin
                if (delay_left==0) begin
                    mem_rsp_data<=saved_response;
                    mem_rsp_error<=saved_error;
                    mem_rsp_valid<=1;
                    pending<=0;
                end else delay_left<=delay_left-1;
            end
            if (mem_valid && mem_ready) begin
                if (pending || mem_rsp_valid) $fatal(1,"duplicate backend request");
                transfers<=transfers+1;
                saved_error=inject_error || mem_addr[3:0]!=0;
                saved_response=0;
                for (int b=0;b<16;b++) begin
                    if (mem_strb[b] && !saved_error) memory[int'(mem_addr)+b]=mem_data[b*8+:8];
                    saved_response[b*8+:8]=memory[int'(mem_addr)+b];
                end
                pending<=1;
                delay_left<=3;
            end
        end
    end
    task automatic transaction(input int addr, input logic [15:0] strb,
        input logic [127:0] data, input bit error_expected, input bit miss_expected);
        int before_count;
        logic [127:0] expected, held;
        @(negedge clk);
        before_count=transfers;
        req_addr=27'(addr); req_strb=strb; req_data=data; req_valid=1;
        do @(posedge clk); while (!req_ready);
        @(negedge clk); req_valid=0;
        wait(rsp_valid);
        @(negedge clk);
        if (rsp_error!==error_expected) $fatal(1,"response error mismatch addr=%h",addr);
        for (int b=0;b<16;b++) expected[b*8+:8]=memory[addr+b];
        if (!error_expected && rsp_data!==expected) $fatal(1,"stale read addr=%h",addr);
        if (transfers-before_count != int'(miss_expected)) $fatal(1,"hit/miss mismatch addr=%h",addr);
        held=rsp_data;
        repeat(7) begin
            @(negedge clk);
            if (!rsp_valid || rsp_data!==held || rsp_error!==error_expected || req_ready || mem_valid)
                $fatal(1,"response not held under backpressure");
        end
        rsp_ready=1;
        @(negedge clk); rsp_ready=0;
    endtask
    task automatic reset_all;
        @(negedge clk); rst=1; req_valid=0; rsp_ready=0;
        repeat(3) @(negedge clk);
        rst=0;
    endtask
    initial begin
        for (int b=0;b<4096;b++) memory[b]=8'(b^(b>>8));
        reset_all();
        transaction(0,0,0,0,1);
        transaction(0,0,0,0,0);
        transaction(16,0,0,0,1);
        transaction(256,0,0,0,1); // same index, different tag
        transaction(0,0,0,0,1);
        transaction(16,0,0,0,0); // other index preserved
        transaction(0,16'h0181,128'h0123456789abcdef1020304050607080,0,1);
        transaction(0,0,0,0,1);
        transaction(0,0,0,0,0);
        transaction(16,0,0,0,0);
        inject_error=1;
        transaction(32,0,0,1,1);
        transaction(32,0,0,1,1); // failed reads never populate
        inject_error=0;
        transaction(32,0,0,0,1);
        transaction(32,0,0,0,0);
        inject_error=1;
        transaction(32,16'hffff,'1,1,1); // failed store still invalidates
        inject_error=0;
        transaction(32,0,0,0,1);
        transaction(1,0,0,1,1); // misaligned must not be a false hit
        reset_all();
        transaction(16,0,0,0,1);
        // Reset with a held response and with a backend transaction in flight.
        @(negedge clk); req_addr=16; req_valid=1;
        do @(posedge clk); while (!req_ready);
        @(negedge clk); req_valid=0;
        wait(rsp_valid);
        reset_all();
        transaction(16,0,0,0,1);
        @(negedge clk); req_addr=64; req_valid=1;
        do @(posedge clk); while (!req_ready);
        @(negedge clk); req_valid=0;
        wait(pending);
        reset_all();
        transaction(64,0,0,0,1);
        // Sequential instruction-sized accesses: four reads share one burst.
        for (int line=0;line<16;line++) begin
            transaction(1024+16*line,0,0,0,1);
            repeat(3) transaction(1024+16*line,0,0,0,0);
        end
        $display("PASS DDR burst cache: coherency, aliases, stalls, errors, reset, sequential reuse");
        $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule
