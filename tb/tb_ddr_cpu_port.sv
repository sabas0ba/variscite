`timescale 1ns/1ps
module tb_ddr_cpu_port;
    parameter CPU_HALF=19, MEM_HALF=5;
    logic cpu_clk=0, mem_clk=0, rst=1;
    always #(CPU_HALF) cpu_clk=~cpu_clk;
    always #(MEM_HALF) mem_clk=~mem_clk;
    wire done, found, req_valid, rsp_ready;
    wire [31:0] failure, actual;
    wire [26:0] req_addr;
    wire [127:0] req_data;
    wire [15:0] req_strb;
    logic req_ready=0, rsp_valid=0, rsp_error=0;
    logic [127:0] rsp_data=0;
    logic [127:0] memory[16];
    int cycle=0, delay=0, reads=0, writes=0, mode=0;
    rv32ima_DdrCpuPort #(.ROM_INIT("sim/ddr_cpu_test.hex")) dut (
        .i_cpu_clk(cpu_clk), .i_mem_clk(mem_clk), .i_reset(rst), .i_enable(!rst),
        .o_done(done), .o_found(found), .o_failure(failure), .o_actual(actual),
        .o_req_valid(req_valid), .i_req_ready(req_ready), .o_req_addr(req_addr),
        .o_req_wdata(req_data), .o_req_wstrb(req_strb), .i_rsp_valid(rsp_valid),
        .o_rsp_ready(rsp_ready), .i_rsp_data(rsp_data), .i_rsp_error(rsp_error)
    );
    function automatic logic [31:0] pattern(input int index);
        logic [31:0] x;
        x=32'h193a70c5 ^ 32'(index);
        x ^= x<<13; x ^= x>>17; x ^= x<<5;
        return x;
    endfunction
    always @(posedge mem_clk) begin
        if (rst) begin
            req_ready<=0; rsp_valid<=0; rsp_error<=0; rsp_data<=0;
            cycle=0; delay=0; reads=0; writes=0;
            foreach (memory[i]) memory[i]='0;
        end else begin
            cycle++;
            req_ready<=delay==0 && !rsp_valid && cycle%7==0;
            if (rsp_valid && rsp_ready) rsp_valid<=0;
            if (delay>0) begin
                delay--;
                if (delay==0) rsp_valid<=1;
            end
            if (req_valid && req_ready) begin
                int index, lane, word_index;
                if (delay!=0 || rsp_valid || req_addr[3:0]!=0 || req_addr>=256)
                    $fatal(1,"request protocol/address");
                req_ready<=0;
                index=int'(req_addr>>4);
                rsp_error<=0; rsp_data<=0;
                delay=3+cycle%5;
                if (req_strb!=0) begin
                    word_index=writes%64;
                    lane=word_index%4;
                    if (req_strb!=(16'hf<<(lane*4)) || index!=word_index/4 ||
                        req_data[32*lane+:32]!=(writes>=128 ?
                            (writes==128 ? 32'h05a00513:32'h00008067) :
                            writes<64 ? pattern(word_index) : ~pattern(word_index)))
                        $fatal(1,"CPU write sequence/data/mask");
                    writes++;
                    if (mode==3 && writes==5) rsp_error<=1;
                    else for (int b=0; b<16; b++)
                        if (req_strb[b]) memory[index][8*b+:8]=req_data[8*b+:8];
                end else begin
                    word_index=reads>=128 ? reads-128 : 63-reads%64;
                    if (index!=word_index/4 || writes!=(reads>=128 ? 130 : reads<64 ? 64:128))
                        $fatal(1,"CPU reverse read sequence");
                    reads++;
                    rsp_data<=memory[index];
                    if (mode==1 && reads==5) rsp_data[32*(word_index%4)]<=~memory[index][32*(word_index%4)];
                    if (mode==2 && reads==5) rsp_error<=1;
                    if ((mode==4 && reads==129) || (mode==5 && reads==130)) rsp_error<=1;
                end
            end
        end
    end
    initial begin
        // Cancel a real CPU request after the backend accepts it, before response.
        repeat (8) @(negedge cpu_clk); rst=0;
        wait(delay>0); @(negedge mem_clk); rst=1;
        for (mode=0; mode<6; mode++) begin
            rst=1; repeat (8) @(negedge cpu_clk); rst=0;
            wait(done); @(negedge cpu_clk);
            if (mode==0) begin
                if (!found || reads!=130 || writes!=130 || failure!=0 || actual!=0)
                    $fatal(1,"CPU diagnostic normal result");
            end else begin
                if (found || failure!=(mode>=4 ? 32'h80000000+32'((mode-4)*4) :
                                      mode==3 ? 32'h80000010:32'h800000ec) ||
                    actual!=(mode>=4 ? 32'd1 : mode==3 ? 32'd7 : mode==2 ? 32'd5 : pattern(59)^1))
                    $fatal(1,"CPU diagnostic failure result mode=%0d address=%h actual=%h",mode,failure,actual);
            end
        end
        $display("DDR CPU port PASS: CPU ROM, mixed/inverted data, reverse reads, DDR execution, CDC, fetch/read/write faults");
        $finish;
    end
    initial begin #10000000; $fatal(1,"CPU diagnostic timeout"); end
endmodule
