`timescale 1ns/1ps
// CPU -> word CDC -> actual controller, with a command-level x16 BL8 model.
module tb_ddr_cpu_probe;
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
    logic [127:0] memory[16];
    int cycles=0, last_ref=0, refs=0, writes=0, reads=0, pending=0, mode=0;
    int row=0, active_bank=0, write_key=0, activated=0, last_access=0;
    bit row_open=0;
    rv32ima_DdrCpuProbe #(.ROM_INIT("sim/ddr_cpu_test.hex")) dut (
        .i_cpu_clk(cpu_clk), .i_clk(clk), .i_reset(rst), .i_enable(!rst),
        .i_read_data(read_data), .i_read_valid(read_valid), .o_done(done), .o_found(found),
        .o_failure(failure), .o_actual(actual),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_odt(odt), .o_data(data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(dqs_enable), .o_dqs_pattern(dqs_pattern)
    );
    function automatic logic [31:0] pattern(input int index);
        logic [31:0] x;
        x=32'h193a70c5 ^ 32'(index);
        x ^= x<<13; x ^= x>>17; x ^= x<<5;
        return x;
    endfunction
    always @(posedge clk) begin
        read_data<=0; read_valid<=0;
        if (rst) begin
            cycles=0; last_ref=0; refs=0; reads=0; writes=0; pending=0; row_open=0;
            foreach (memory[i]) memory[i]=0;
        end else begin
            cycles++;
            if (cycles-last_ref>315) $fatal(1,"CPU workload missed refresh deadline");
            if (pending>0) begin
                pending--;
                if (pending==0) begin
                    read_data<=returning;
                    read_valid<=((mode==2 && reads==5) || (mode==3 && reads==129)) ? 0:3;
                end
            end
            if (cmd_valid) begin
                case (cmd)
                    1: begin
                        if (row_open) $fatal(1,"REF with open row");
                        last_ref=cycles; refs++;
                    end
                    2: begin
                        if (row_open && cycles-last_access<10) $fatal(1,"early PRE");
                        row_open=0;
                    end
                    3: begin
                        if (row_open) $fatal(1,"ACT with open row");
                        row=int'(addr); active_bank=int'(bank); activated=cycles; row_open=1;
                    end
                    4,5: begin
                        int key;
                        if (!row_open || cycles-activated<4 || bank!=3'(active_bank))
                            $fatal(1,"ACT/access timing or bank");
                        key=(active_bank<<20)|(row<<7)|(int'(addr)>>3);
                        if (key>=16 || addr[2:0]!=0) $fatal(1,"CPU address mapping");
                        last_access=cycles;
                        if (cmd==4) write_key=key;
                        else begin
                            int word_index;
                            word_index=reads>=128 ? reads-128:63-reads%64;
                            if (key!=word_index/4) $fatal(1,"CPU READ address sequence");
                            returning=memory[key];
                            reads++;
                            if (mode==1 && reads==5) returning[32*(word_index%4)]^=1'b1;
                            pending=8;
                        end
                    end
                    default: $fatal(1,"unexpected command");
                endcase
            end
            if (dq_enable==15) begin
                int index, lane;
                logic [31:0] expected;
                index=writes%64; lane=index%4;
                expected=writes>=128 ? (writes==128 ? 32'h05a00513:32'h00008067) :
                    writes<64 ? pattern(index):~pattern(index);
                if (write_key!=index/4 || mask!=(16'hffff ^ (16'hf<<(lane*4))) ||
                    data[32*lane+:32]!=expected) $fatal(1,"CPU WRITE data/mask/address");
                for (int b=0; b<16; b++) if (!mask[b]) memory[write_key][8*b+:8]=data[8*b+:8];
                writes++;
            end
        end
    end
    initial begin
        // Reset the entire CPU/CDC/controller path with a READ response pending.
        repeat (8) @(negedge cpu_clk); rst=0;
        wait(pending>0); @(negedge clk); rst=1;
        for (mode=0; mode<4; mode++) begin
            rst=1; repeat (8) @(negedge cpu_clk); rst=0;
            wait(done); @(negedge cpu_clk);
            if (refs<3) $fatal(1,"insufficient refresh exercised");
            if (mode==0) begin
                if (!found || writes!=130 || reads!=130 || failure!=0 || actual!=0)
                    $fatal(1,"normal CPU/controller result");
            end else if (found || failure!=(mode==3 ? 32'h80000000:32'h800000ec) ||
                         actual!=(mode==3 ? 1 : mode==2 ? 5 : pattern(59)^1))
                $fatal(1,"CPU/controller failure mode=%0d address=%h actual=%h",mode,failure,actual);
        end
        $display("DDR CPU controller PASS: CPU execution, commands, masks, refresh, read corruption, data/fetch timeout");
        $finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule
