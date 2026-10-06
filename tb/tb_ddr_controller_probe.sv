module tb_ddr_controller_probe;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic [127:0] read_data=0;
    logic [1:0] read_valid=0;
    wire done, found, cmd_valid;
    wire [127:0] data;
    wire [15:0] mask;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, dqs_pattern;
    wire [3:0] odt, dq_enable, dqs_enable;
    logic [127:0] memory[int unsigned], returning;
    int writes=0, reads=0, refs=0, cycles=0, last_ref=0, pending=0, mode=0;
    int unsigned row=0, active_bank=0, write_key=0;
    rv32ima_DdrControllerProbe #(.HOLD_CYCLES(1024)) dut (
        .i_clk(clk), .i_rst(rst), .i_enable(!rst),
        .i_read_data(read_data), .i_read_valid(read_valid), .o_done(done), .o_found(found),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_odt(odt), .o_data(data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(dqs_enable), .o_dqs_pattern(dqs_pattern)
    );
    always @(posedge clk) begin
        read_data<=0; read_valid<=0;
        if (rst) begin
            writes=0; reads=0; refs=0; cycles=0; last_ref=0; pending=0;
            memory.delete();
        end else begin
            cycles++;
            if (cycles-last_ref>384) $fatal(1,"refresh deadline");
            if (pending!=0) begin
                if (pending==1) begin
                    read_data<=returning;
                    read_valid<=(mode==2 && reads==20) ? 0 : 3;
                end
                pending--;
            end
            if (cmd_valid) begin
                if (cmd==3'b001) begin last_ref=cycles; refs++; end
                if (cmd==3'b011) begin row=32'(addr); active_bank=32'(bank); end
                if (cmd==3'b100 || cmd==3'b101) begin
                    int unsigned key, index;
                    key=(active_bank<<20)|(row<<7)|(32'(addr)>>3);
                    index=32'(cmd==3'b100 ? writes : reads);
                    if (active_bank!=(index & 7) || row!=index || addr!=14'(index*8))
                        $fatal(1,"probe address sequence");
                    if (cmd==3'b100) begin
                        if (reads!=0 || writes>=32) $fatal(1,"rewrite during verification");
                        if (writes==1 && refs<4) $fatal(1,"no refresh while response blocked");
                        write_key=key;
                    end else begin
                        if (writes!=32 || memory.exists(key)==0) $fatal(1,"unwritten read");
                        returning=memory[key];
                        if (mode==1 && reads==13) returning[67]=~returning[67];
                        pending=8; reads++;
                    end
                end
            end
            if (dq_enable==15) begin
                if (mask!=0 || memory.exists(write_key)!=0) $fatal(1,"write mask/duplicate");
                memory[write_key]=data; writes++;
            end
        end
    end
    initial begin
        for (int scenario=0;scenario<3;scenario++) begin
            @(negedge clk); rst=1; mode=scenario;
            repeat(3) @(negedge clk); rst=0;
            wait(done); @(negedge clk);
            if (found!==(scenario==0) || writes!=32 || reads!=32 || refs<8)
                $fatal(1,"probe scenario=%0d found=%b",scenario,found);
            $display("probe scenario=%0d cycles=%0d refs=%0d",scenario,cycles,refs);
        end
        $display("DDR controller probe PASS: 32 writes/readbacks, hold, backpressure, sticky corruption/timeout");
        $finish;
    end
    initial begin #300000; $fatal(1,"timeout"); end
endmodule
