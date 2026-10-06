`timescale 1ns/1ps
module tb_ddr_cpu_access;
    logic clk=0, cpu_clk=0, rst=1;
    always #5 clk=~clk;
    always #19 cpu_clk=~cpu_clk;
    logic [127:0] read_data=0, returning;
    logic [1:0] read_valid=0;
    wire done, found, cmd_valid;
    wire [31:0] failure, actual;
    wire [127:0] data;
    wire [15:0] mask;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, dqs_pattern;
    wire [3:0] odt, dq_enable, dqs_enable;
    logic [127:0] memory[int unsigned];
    logic [15:0] byte_lanes=0;
    int cycles=0, last_ref=0, refs=0, writes=0, reads=0, pending=0, mode=0;
    int unsigned row=0, active_bank=0, write_key=0;
    int tail_reads=0, tail_writes=0;
    rv32ima_DdrCpuProbe #(.ROM_INIT("sim/ddr_cpu_access.hex")) dut (
        .i_cpu_clk(cpu_clk), .i_clk(clk), .i_reset(rst), .i_enable(!rst),
        .i_read_data(read_data), .i_read_valid(read_valid), .o_done(done), .o_found(found),
        .o_failure(failure), .o_actual(actual),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_odt(odt), .o_data(data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(dqs_enable), .o_dqs_pattern(dqs_pattern)
    );
    always @(posedge clk) begin
        read_data<=0; read_valid<=0;
        if (rst) begin
            cycles=0; last_ref=0; refs=0; reads=0; writes=0; pending=0;
            tail_reads=0; tail_writes=0; byte_lanes=0; memory.delete();
        end else begin
            cycles++;
            if (cycles-last_ref>315) $fatal(1,"access diagnostic missed refresh");
            if (pending>0) begin
                pending--;
                if (pending==0) begin
                    read_data<=returning;
                    read_valid<=(mode==2 && reads==1) ? 0:3;
                end
            end
            if (cmd_valid) begin
                if (cmd==1) begin last_ref=cycles; refs++; end
                if (cmd==3) begin row=int'(addr); active_bank=int'(bank); end
                if (cmd==4 || cmd==5) begin
                    int unsigned key;
                    key=(active_bank<<20)|(row<<7)|(int'(addr)>>3);
                    // An out-of-range CPU access must never alias physical address zero.
                    if (!((key>=32'hff && key<=32'h102) || key==32'h7fffff))
                        $fatal(1,"unexpected physical access %h",key);
                    if (cmd==4) write_key=key;
                    else begin
                        if (!memory.exists(key)) $fatal(1,"read before initialization");
                        returning=memory[key]; reads++;
                        if (key==32'h7fffff) tail_reads++;
                        if (mode==1 && reads==1) returning[0]^=1'b1;
                        pending=8;
                    end
                end
            end
            if (dq_enable==15) begin
                if (!memory.exists(write_key)) memory[write_key]=0;
                for (int b=0; b<16; b++) if (!mask[b]) memory[write_key][8*b+:8]=data[8*b+:8];
                if ($countones(~mask)==1) byte_lanes|=~mask;
                if (write_key==32'h7fffff) tail_writes++;
                writes++;
            end
        end
    end
    initial begin
        for (mode=0; mode<3; mode++) begin
            rst=1; repeat (8) @(negedge cpu_clk); rst=0;
            wait(done); @(negedge cpu_clk);
            if (mode==0) begin
                if (!found || failure!=0 || actual!=0 || byte_lanes!=16'hffff ||
                    tail_reads<6 || tail_writes<5 || refs<3)
                    $fatal(1,"access result found=%b failure=%h actual=%h byte_lanes=%h tail=%0d/%0d",
                        found,failure,actual,byte_lanes,tail_reads,tail_writes);
                $display("CPU access normal: writes=%0d reads=%0d refresh=%0d",writes,reads,refs);
            end else if (found || failure!=32'h80001000 || actual!=(mode==2 ? 5:32'ha4))
                $fatal(1,"fault detection mode=%0d address=%h actual=%h",mode,failure,actual);
        end
        $display("DDR CPU access PASS: byte/half/word, misalignment, guards, last bytes, faults, atomics, corruption/timeout");
        $finish;
    end
    initial begin #100000000; $fatal(1,"timeout"); end
endmodule
