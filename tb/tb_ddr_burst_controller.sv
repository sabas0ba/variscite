module tb_ddr_burst_controller;
    logic clk=0, rst=1, enable=0;
    always #5 clk=~clk;
    logic req_valid=0, rsp_ready=0;
    logic [26:0] req_addr=0;
    logic [127:0] req_data=0, read_data=0;
    logic [15:0] req_strb=0;
    logic [1:0] read_valid=0;
    wire req_ready, rsp_valid, rsp_error, cmd_valid;
    wire [127:0] rsp_data, write_data;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, dqs_pattern;
    wire [3:0] odt, dq_enable, dqs_enable;
    wire [15:0] mask;
    logic [127:0] memory[int unsigned], golden[int unsigned];
    logic [127:0] response_word, accepted_data, held_data;
    logic held_error, was_held=0, active=0;
    logic [26:0] accepted_addr;
    logic [15:0] accepted_strb;
    int cycles=0, last_ref=0, last_act=-100, last_pre=-100, last_write=-100;
    int refreshes=0, accepts=0, responses=0, pending=0, fault=0;
    int unsigned row=0, active_bank=0, write_key=0;

    rv32ima_DdrBurstController dut (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_req_valid(req_valid), .o_req_ready(req_ready), .i_req_addr(req_addr),
        .i_req_data(req_data), .i_req_strb(req_strb),
        .o_rsp_valid(rsp_valid), .i_rsp_ready(rsp_ready), .o_rsp_data(rsp_data), .o_rsp_error(rsp_error),
        .i_read_data(read_data), .i_read_valid(read_valid),
        .o_cmd_valid(cmd_valid), .o_cmd(cmd), .o_addr(addr), .o_bank(bank),
        .o_read(read_gate), .o_odt(odt), .o_data(write_data), .o_mask(mask),
        .o_dq_enable(dq_enable), .o_dqs_enable(dqs_enable), .o_dqs_pattern(dqs_pattern)
    );

    always @(posedge clk) begin
        read_valid <= 0;
        read_data <= 0;
        if (rst || !enable) begin
            cycles=0; last_ref=0; last_act=-100; last_pre=-100; last_write=-100;
            active=0; pending=0; was_held=0; accepts=0; responses=0; refreshes=0;
        end else begin
            cycles++;
            if (cycles-last_ref > 384) $fatal(1,"refresh overdue, including backpressure");
            if (was_held && (!rsp_valid || rsp_data !== held_data || rsp_error !== held_error))
                $fatal(1,"response changed under backpressure");
            was_held = rsp_valid && !rsp_ready;
            held_data = rsp_data; held_error = rsp_error;
            if (req_valid && req_ready) begin
                if (accepts != responses) $fatal(1,"multiple outstanding requests");
                accepts++;
                accepted_addr=req_addr; accepted_data=req_data; accepted_strb=req_strb;
            end
            if (rsp_valid && rsp_ready) begin
                responses++;
                if (responses > accepts || active) $fatal(1,"unsolicited/early response");
            end
            if (pending != 0) begin
                if (pending == 2 && fault != 3) begin
                    read_data <= response_word; read_valid <= 1;
                end
                if (pending == 1 && fault != 2 && fault != 3) begin
                    read_data <= response_word ^ (fault == 1 ? 128'h00ff : 128'b0);
                    read_valid <= fault == 1 ? 3 : 2;
                end
                pending--;
            end
            if (cmd_valid) begin
                if (last_ref != 0 && cycles-last_ref < 32) $fatal(1,"tRFC guard");
                case (cmd)
                    3'b001: begin
                        if (active || cycles-last_pre < 4) $fatal(1,"REF before PRE/tRP");
                        last_ref=cycles; refreshes++;
                    end
                    3'b011: begin
                        if (active || cycles-last_pre < 4 || bank != accepted_addr[26:24] ||
                            addr != {1'b0,accepted_addr[23:11]}) $fatal(1,"ACT address/tRP");
                        active=1; active_bank=32'(bank); row=32'(addr); last_act=cycles;
                    end
                    3'b100,3'b101: begin
                        int unsigned key;
                        key=(active_bank<<20)|(row<<7)|(32'(addr)>>3);
                        if (!active || cycles-last_act < 4 || bank != 3'(active_bank) ||
                            addr != {4'b0,accepted_addr[10:4],3'b0} ||
                            key != (32'(accepted_addr)>>4)) $fatal(1,"column address/tRCD");
                        if (cmd == 3'b100) begin
                            if (accepted_strb == 0) $fatal(1,"unexpected WRITE");
                            write_key=key; last_write=cycles;
                        end else begin
                            if (accepted_strb != 0 || pending != 0 || memory.exists(key)==0)
                                $fatal(1,"invalid READ");
                            response_word=memory[key]; pending=8;
                        end
                    end
                    3'b010: begin
                        if (!active || addr != 14'h400 || cycles-last_act < 4 ||
                            cycles-last_write < 10) $fatal(1,"PRE recovery");
                        active=0; last_pre=cycles;
                    end
                    default: $fatal(1,"unknown command");
                endcase
            end
            if (dq_enable != 0) begin
                if (cycles-last_write != 2 || dq_enable != 15 || dqs_enable != 15 ||
                    dqs_pattern != 8'haa || odt != 15 || mask != ~accepted_strb ||
                    write_data != accepted_data) $fatal(1,"WRITE data/mask/timing");
                if (memory.exists(write_key)==0) memory[write_key]=0;
                for (int b=0;b<16;b++)
                    if (!mask[b]) memory[write_key][b*8+:8]=write_data[b*8+:8];
            end
        end
    end

    task automatic transfer(input logic [26:0] address, input logic [127:0] value,
                            input logic [15:0] strb, input int hold_cycles=0,
                            input bit expect_error=0);
        int unsigned key;
        logic [127:0] expected;
        key=32'(address)>>4;
        expected=0;
        if (!expect_error) begin
            if (golden.exists(key)==0) golden[key]=0;
            if (strb!=0) begin
                for (int b=0;b<16;b++)
                    if (strb[b]) golden[key][8*b+:8]=value[8*b+:8];
            end else expected=golden[key];
        end
        @(negedge clk);
        req_valid=1; req_addr=address; req_data=value; req_strb=strb;
        do @(posedge clk); while (!req_ready);
        @(negedge clk);
        req_valid=0; req_addr='1; req_data='1; req_strb='1;
        wait(rsp_valid); @(negedge clk);
        if (rsp_error !== expect_error || rsp_data !== (expect_error ? 128'b0 : expected))
            $fatal(1,"response mismatch addr=%h fault=%0d error=%b data=%h expected=%h",
                   address,fault,rsp_error,rsp_data,expected);
        repeat(hold_cycles) @(negedge clk);
        rsp_ready=1; @(negedge clk); rsp_ready=0;
    endtask

    initial begin
        repeat(3) @(negedge clk); rst=0;
        repeat(5) @(negedge clk);
        if (cmd_valid || req_ready || rsp_valid) $fatal(1,"disabled controller active");
        enable=1;
        // Unaligned requests fail without opening a bank.
        transfer(27'd3,0,0,0,1);
        transfer(0,128'h0123456789abcdef_fedcba9876543210,16'hffff);
        transfer(0,0,0,1200);
        if (refreshes < 4) $fatal(1,"no refresh under response backpressure");
        for (int b=0;b<16;b++) begin
            transfer(0,128'hf0e1d2c3b4a59687_78695a4b3c2d1e0f ^ 128'(b),16'(1<<b));
            transfer(0,0,0);
        end
        for (int bit_index=4;bit_index<27;bit_index++) begin
            transfer(27'b1<<bit_index,128'(bit_index)*128'h1020304050607081,16'hffff);
            transfer(27'b1<<bit_index,0,0);
        end
        transfer(27'h7fffff0,128'hff00112233445566_778899aabbccddee,16'hffff);
        transfer(27'h7fffff0,0,0);
        fault=1; transfer(0,0,0); // duplicate lane0 valid must not overwrite its first capture
        fault=2; transfer(0,0,0,900,1); // missing lane1
        fault=3; transfer(0,0,0,0,1); // no valid
        fault=0; transfer(0,0,0); // recover on next request
        repeat(1000) @(negedge clk);
        if (accepts!=responses || active) $fatal(1,"transaction accounting");
        // Reset before read data arrives must cancel the in-flight transaction.
        @(negedge clk); req_valid=1; req_addr=0; req_strb=0;
        do @(posedge clk); while(!req_ready);
        @(negedge clk); req_valid=0;
        wait(cmd_valid && cmd==3'b101); @(negedge clk); rst=1; enable=0;
        repeat(3) @(negedge clk);
        rst=0; enable=1;
        transfer(0,0,0);
        // Reset with a stalled response cancels it; reinitialization is external.
        @(negedge clk); req_valid=1; req_addr=0; req_strb=0;
        do @(posedge clk); while(!req_ready);
        @(negedge clk); req_valid=0;
        wait(rsp_valid); @(negedge clk); rst=1; enable=0;
        repeat(3) @(negedge clk);
        rst=0; enable=1;
        transfer(0,0,0);
        $display("DDR burst controller PASS: addresses, masks, backpressure refresh, timeout, reset, lane capture");
        $finish;
    end
    initial begin #300000; $fatal(1,"timeout"); end
endmodule
