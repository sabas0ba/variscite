// Shortened full-capacity algorithm, real word port/CDC/controller, PHY model.
module tb_ddr_full_probe;
    localparam integer WORDS=64;
    logic clk=0, cpu_clk=0, rst=1;
    always #5 clk=~clk;
    always #19 cpu_clk=~cpu_clk;
    logic [127:0] read_data=0;
    logic [1:0] read_valid=0;
    wire done, found, cmd_valid;
    wire [31:0] failure, actual;
    wire [127:0] data;
    wire [15:0] mask;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [3:0] dq_enable;
    logic [127:0] memory[int unsigned], returning;
    integer writes=0, reads=0, refs=0, cycles=0, last_ref=0, pending=0, mode=0;
    integer row=0, active_bank=0, write_key=0;
    integer retries=0, retry_index=0;
    logic expect_retry=0, suppress_return=0;
    rv32ima_DdrWordProbe #(.HOLD_CYCLES(1024), .FULL_WORDS(WORDS)) dut (
        .i_cpu_clk(cpu_clk), .i_clk(clk), .i_reset(rst), .i_enable(!rst),
        .i_read_data(read_data), .i_read_valid(read_valid), .o_done(done), .o_found(found),
        .o_failure(failure), .o_actual(actual),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(), .o_odt(), .o_data(data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(), .o_dqs_pattern()
    );
    always @(posedge clk) begin
        read_valid<=0;
        if (rst) begin
            writes=0; reads=0; refs=0; cycles=0; last_ref=0; pending=0;
            retries=0; expect_retry=0; suppress_return=0;
            memory.delete();
        end else begin
            cycles++;
            if (cycles-last_ref>384) $fatal(1,"refresh deadline");
            if (pending!=0) begin
                if (pending==1) begin
                    read_data<=returning;
                    read_valid<=suppress_return ? 0 : 3;
                end
                pending--;
            end
            if (cmd_valid) begin
                if (cmd==3'b001) begin last_ref=cycles; refs++; end
                if (cmd==3'b011) begin row=32'(addr); active_bank=32'(bank); end
                if (cmd==3'b100 || cmd==3'b101) begin
                    integer key, index;
                    key=(active_bank<<20)|(row<<7)|(32'(addr)>>3);
                    index=cmd==3'b100 ? writes%WORDS : expect_retry ? retry_index : WORDS-1-reads%WORDS;
                    if (key!=index/4) $fatal(1,"scan order/address");
                    // Emulate one stuck address line after checking the PHY CA.
                    if (mode==3) key=key & ~4;
                    if (cmd==3'b100) begin
                        if (expect_retry) $fatal(1,"write before retry");
                        if (reads!=(writes/WORDS)*WORDS || writes>=2*WORDS)
                            $fatal(1,"rewrite before all words verified");
                        write_key=key;
                    end else begin
                        if (writes!=((reads-(expect_retry ? 1 : 0))/WORDS+1)*WORDS || memory.exists(key)==0)
                            $fatal(1,"read before full write pass");
                        returning=memory[key];
                        suppress_return=0;
                        if (expect_retry) begin
                            retries++;
                            expect_retry=0;
                            if (mode==4) suppress_return=1;
                        end else begin
                            if (((mode==1 || mode==4) && reads==13) ||
                                (mode==5 && reads==WORDS-1) || (mode==6 && reads==2*WORDS-1))
                                returning[(index%4)*32+3]=~returning[(index%4)*32+3];
                            suppress_return=(mode==2 && reads==19);
                            if (((mode==1 || mode==4) && reads==13) || suppress_return || (mode==3 && reads==16) ||
                                (mode==5 && reads==WORDS-1) || (mode==6 && reads==2*WORDS-1)) begin
                                expect_retry=1;
                                retry_index=index;
                            end
                            reads++;
                        end
                        pending=8;
                    end
                end
            end
            if (dq_enable==15) begin
                logic [31:0] expected_word;
                integer lane;
                lane=writes%4;
                expected_word=32'h193a70c5 ^ 32'(writes%WORDS);
                if (writes>=WORDS) expected_word=~expected_word;
                if (mask!==(16'hffff ^ (16'h000f << (lane*4))) ||
                    data!== (128'(expected_word) << (lane*32))) $fatal(1,"pattern/mask");
                if (memory.exists(write_key)==0) memory[write_key]=0;
                for (integer b=0;b<16;b++)
                    if (!mask[b]) memory[write_key][b*8+:8]=data[b*8+:8];
                writes++;
            end
        end
    end
    initial begin
        for (integer scenario=0;scenario<7;scenario++) begin
            @(negedge clk); rst=1; mode=scenario;
            repeat(5) @(negedge clk); rst=0;
            wait(done); @(negedge clk);
            if (found!==(scenario==0) || writes!=2*WORDS || reads!=2*WORDS || refs<8)
                $fatal(1,"full probe scenario=%0d found=%b writes=%0d reads=%0d",scenario,found,writes,reads);
            if ((scenario==0 && failure!==0) ||
                (scenario==1 && (failure!==32'h88000032 || actual!==(32'h193a70c5 ^ 32'd50 ^ 32'd8))) ||
                (scenario==2 && (failure!==32'hc800002c || actual!==0)) ||
                (scenario==3 && failure!==32'h8200002f) ||
                (scenario==4 && failure!==32'h84000032) ||
                (scenario==5 && (failure!==32'h88000000 || actual!==(32'h193a70c5 ^ 32'd8))) ||
                (scenario==6 && (failure!==32'ha8000000 || actual!==((~32'h193a70c5) ^ 32'd8))))
                $fatal(1,"first failure report %h %h",failure,actual);
            if (retries!=(scenario==0 ? 0 : 1)) $fatal(1,"retry count");
            $display("full probe scenario=%0d cycles=%0d refs=%0d writes=%0d reads=%0d",scenario,cycles,refs,writes,reads);
        end
        $display("DDR full probe PASS: complementary passes, reverse read, corruption, timeout, alias");
        $finish;
    end
    initial begin #3000000; $fatal(1,"full probe watchdog"); end
endmodule
