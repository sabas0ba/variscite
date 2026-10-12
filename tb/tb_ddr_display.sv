// Actual DDR controller, arbitration, DMA and dual-clock burst FIFO.
// The DDR command model supplies lane data; the consumer checks 800x480 scan
// timing at one pixel clock edge per three controller cycles.
module tb_ddr_display;
    localparam int FRAME_BURSTS=48000, FIFO_BURSTS=256;
    localparam logic [26:0] BASE=27'h7c00000;
    logic clk=0, rst=1, enable=0;
    always #5 clk=~clk; // three 99 MHz controller cycles per 33 MHz pixel
    logic start=0;
    logic [26:0] frame_base=BASE;
    logic [15:0] frame_bursts=16'(FRAME_BURSTS);
    wire busy, error, stream_valid, stream_first, stream_last;
    wire [127:0] stream_data;
    wire stream_ready;
    logic test_ready=0, pixel_clk=0, pixel_ready=0;
    wire fifo_ready, fifo_valid;
    wire [127:0] fifo_data;
    wire [8:0] fifo_level;
    wire [1:0] req_ready, rsp_valid, rsp_error;
    logic [1:0] req_valid, rsp_ready;
    logic [26:0] req_addr[2];
    logic [127:0] req_data[2];
    logic [15:0] req_strb[2];
    wire [127:0] rsp_data[2];
    logic cpu_valid=0, cpu_ready=1, urgent=0;
    logic [26:0] cpu_addr=0;
    logic [127:0] cpu_data=0;
    logic [15:0] cpu_strb=0;
    wire dma_valid, dma_ready;
    wire [26:0] dma_addr;
    wire mem_valid, mem_ready, mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
    wire [26:0] mem_addr;
    wire [127:0] mem_data, mem_rsp_data, write_data;
    wire [15:0] mem_strb, mask;
    wire cmd_valid;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    wire [7:0] read_gate, dqs_pattern;
    wire [3:0] odt, dq_enable, dqs_enable;
    logic [127:0] read_data=0;
    logic [1:0] read_valid=0;

    assign req_valid={dma_valid,cpu_valid};
    assign req_addr[0]=cpu_addr;
    assign req_addr[1]=dma_addr;
    assign req_data[0]=cpu_data;
    assign req_data[1]=0;
    assign req_strb[0]=cpu_strb;
    assign req_strb[1]=0;
    assign rsp_ready={dma_ready,cpu_ready};
    rv32ima_DdrFrameReader reader (
        .i_clk(clk),.i_rst(rst),.i_start(start),.i_base(frame_base),.i_bursts(frame_bursts),
        .o_busy(busy),.o_error(error),.o_req_valid(dma_valid),.i_req_ready(req_ready[1]),
        .o_req_addr(dma_addr),.i_rsp_valid(rsp_valid[1]),.o_rsp_ready(dma_ready),
        .i_rsp_data(rsp_data[1]),.i_rsp_error(rsp_error[1]),.o_valid(stream_valid),
        .i_ready(stream_ready),.o_data(stream_data),.o_first(stream_first),.o_last(stream_last)
    );
    rv32ima_DdrBurstArbiter arbiter (
        .i_clk(clk),.i_rst(rst),.i_req_valid(req_valid),.o_req_ready(req_ready),
        .i_req_addr(req_addr),.i_req_data(req_data),.i_req_strb(req_strb),
        .o_rsp_valid(rsp_valid),.i_rsp_ready(rsp_ready),.o_rsp_data(rsp_data),.o_rsp_error(rsp_error),
        .i_display_urgent(urgent),.o_mem_valid(mem_valid),.i_mem_ready(mem_ready),
        .o_mem_addr(mem_addr),.o_mem_data(mem_data),.o_mem_strb(mem_strb),
        .i_mem_rsp_valid(mem_rsp_valid),.o_mem_rsp_ready(mem_rsp_ready),
        .i_mem_rsp_data(mem_rsp_data),.i_mem_rsp_error(mem_rsp_error)
    );
    rv32ima_DdrBurstController controller (
        .i_clk(clk),.i_rst(rst),.i_enable(enable),.i_req_valid(mem_valid),.o_req_ready(mem_ready),
        .i_req_addr(mem_addr),.i_req_data(mem_data),.i_req_strb(mem_strb),
        .o_rsp_valid(mem_rsp_valid),.i_rsp_ready(mem_rsp_ready),.o_rsp_data(mem_rsp_data),.o_rsp_error(mem_rsp_error),
        .i_read_data(read_data),.i_read_valid(read_valid),.o_cmd_valid(cmd_valid),.o_cmd(cmd),.o_addr(addr),.o_bank(bank),
        .o_read(read_gate),.o_odt(odt),.o_data(write_data),.o_mask(mask),
        .o_dq_enable(dq_enable),.o_dqs_enable(dqs_enable),.o_dqs_pattern(dqs_pattern)
    );
    rv32ima_DdrDisplayFifo fifo (
        .i_mem_clk(clk),.i_pixel_clk(pixel_clk),.i_reset(rst),
        .i_valid(stream_valid&&check_display),.o_ready(fifo_ready),.i_data(stream_data),.o_level(fifo_level),
        .o_valid(fifo_valid),.i_ready(pixel_ready),.o_data(fifo_data)
    );
    assign stream_ready=check_display ? fifo_ready : test_ready;

    function automatic logic [127:0] pattern(input logic [26:0] address);
        for(int b=0;b<16;b++) pattern[b*8+:8]=8'((32'(address)>>4) ^ (32'(address)>>12) ^ (b*37));
    endfunction
    logic [127:0] memory[int unsigned];
    logic [127:0] expected[2], held[2];
    logic [1:0] held_error=0, was_held=0, outstanding=0;
    logic [26:0] accepted_addr;
    logic [127:0] accepted_data, returning_data;
    logic [15:0] accepted_strb;
    logic mem_held=0, active=0;
    logic [26:0] held_addr;
    logic [127:0] held_write;
    logic [15:0] held_strb;
    int cycles=0, last_ref=0, last_pre=-100, last_act=-100, last_write=-100;
    int pending=0, row=0, active_bank=0, write_key=0;
    int cpu_responses=0, cpu_accepts=0, dma_accepts=0, refreshes=0;
    int frame_words=0, received_words=0, min_level=FIFO_BURSTS;
    logic [26:0] reference_base;
    int reference_bursts=0;
    bit check_display=0, inject_error=0, error_return=0;
    int fault_index=5;

    always @(posedge clk) begin
        read_valid<=0;
        if(rst) begin
            cycles=0; last_ref=0; last_pre=-100; last_act=-100; last_write=-100;
            pending=0; active=0; outstanding=0; was_held=0; mem_held=0;
            cpu_responses=0; cpu_accepts=0; dma_accepts=0; refreshes=0; received_words=0;
            memory.delete();
        end else begin
            cycles++;
            if(start&&!busy) begin
                reference_base=frame_base; reference_bursts=int'(frame_bursts); received_words=0;
            end
            if(enable && cycles-last_ref>315) $fatal(1,"refresh overdue");
            for(int c=0;c<2;c++) begin
                if(was_held[c] && (!rsp_valid[c] || rsp_data[c]!==held[c] || rsp_error[c]!==held_error[c]))
                    $fatal(1,"client %0d stalled response changed",c);
                was_held[c]=rsp_valid[c]&&!rsp_ready[c]; held[c]=rsp_data[c]; held_error[c]=rsp_error[c];
                if(req_valid[c]&&req_ready[c]) begin
                    if(outstanding[c]) $fatal(1,"duplicate client request");
                    outstanding[c]=1;
                    if(c==0) begin
                        cpu_accepts++;
                        expected[c]=req_strb[c]!=0 ? 0 : memory[32'(req_addr[c]>>4)];
                    end else dma_accepts++;
                end
                if(rsp_valid[c]&&rsp_ready[c]) begin
                    if(!outstanding[c]) $fatal(1,"wrong response owner");
                    outstanding[c]=0;
                    if(c==0) begin
                        cpu_responses++;
                        if(rsp_error[c] || rsp_data[c]!==expected[c]) $fatal(1,"CPU data/mask mismatch");
                    end
                end
            end
            if(mem_held && (!mem_valid || mem_addr!==held_addr || mem_data!==held_write || mem_strb!==held_strb))
                $fatal(1,"arbiter request changed under stall");
            mem_held=mem_valid&&!mem_ready; held_addr=mem_addr; held_write=mem_data; held_strb=mem_strb;
            if(mem_valid&&mem_ready) begin
                accepted_addr=mem_addr; accepted_data=mem_data; accepted_strb=mem_strb;
            end
            if(pending!=0) begin
                if(pending==2) begin read_data<=returning_data; read_valid<=1; end
                if(pending==1 && !error_return) begin read_data<=returning_data; read_valid<=2; end
                pending--;
            end
            if(cmd_valid) begin
                if(last_ref!=0 && cycles-last_ref<32) $fatal(1,"tRFC");
                case(cmd)
                    3'b001: begin
                        if(active || cycles-last_pre<4) $fatal(1,"REF/tRP");
                        last_ref=cycles; refreshes++;
                    end
                    3'b011: begin
                        if(active || cycles-last_pre<4) $fatal(1,"ACT/tRP");
                        active=1; row=int'(addr); active_bank=int'(bank); last_act=cycles;
                    end
                    3'b100,3'b101: begin
                        int unsigned key;
                        key=(active_bank<<20)|(row<<7)|(int'(addr)>>3);
                        if(!active || cycles-last_act<4 || key!=(32'(accepted_addr)>>4)) $fatal(1,"DDR address/tRCD");
                        if(cmd==3'b100) begin write_key=key; last_write=cycles; end
                        else begin
                            returning_data=accepted_addr>=BASE ? pattern(accepted_addr) : memory[key];
                            error_return=inject_error && accepted_addr==BASE+27'(fault_index*16);
                            pending=8;
                        end
                    end
                    3'b010: begin
                        if(!active || cycles-last_write<10) $fatal(1,"PRE recovery");
                        active=0; last_pre=cycles;
                    end
                    default: $fatal(1,"unexpected DDR command");
                endcase
            end
            if(dq_enable!=0) begin
                if(cycles-last_write!=2 || mask!==~accepted_strb || write_data!==accepted_data) $fatal(1,"write mapping");
                if(!memory.exists(write_key)) memory[write_key]=0;
                for(int b=0;b<16;b++) if(!mask[b]) memory[write_key][b*8+:8]=write_data[b*8+:8];
            end
            if(stream_valid&&stream_ready) begin
                logic [127:0] value;
                value=(inject_error&&received_words==fault_index) ? 0 : pattern(reference_base+27'(received_words*16));
                if(stream_data!==value || stream_first!==(received_words==0) || stream_last!==(received_words==reference_bursts-1))
                    $fatal(1,"frame ordering/data at burst %0d",received_words);
                received_words++;
            end
        end
    end

    task automatic reset_all;
        @(negedge clk); rst=1; enable=0; start=0; cpu_valid=0; cpu_ready=1;
        test_ready=0; urgent=0; check_display=0; inject_error=0; pixel_clk=0; pixel_ready=0;
        repeat(4) @(negedge clk);
        rst=0; enable=1;
    endtask
    task automatic begin_frame(input logic [26:0] base, input int count);
        @(negedge clk); frame_base=base; frame_bursts=16'(count); start=1;
        @(negedge clk); start=0;
    endtask

    initial begin
        reset_all();
        // Bounds and zero-length rejection, including addition overflow.
        begin_frame(BASE+1,1); if(busy||!error||dma_accepts!=0) $fatal(1,"alignment accepted");
        begin_frame(BASE,0); if(busy||!error||dma_accepts!=0) $fatal(1,"zero accepted");
        begin_frame(27'h7fffff0,2); if(busy||!error||dma_accepts!=0) $fatal(1,"overflow accepted");
        // Error burst preserves its position and stream markers under stalls.
        inject_error=1; begin_frame(BASE,12);
        // Busy start and live configuration changes must not redirect a frame.
        @(negedge clk); start=1; frame_base=0; frame_bursts=16'hffff;
        repeat(5) @(negedge clk);
        start=0;
        while(busy) begin @(negedge clk); test_ready=cycles%11<5; end
        if(!error||received_words!=12) $fatal(1,"error not reported");
        // The final aligned burst at the exclusive 128 MiB boundary is legal.
        inject_error=0; begin_frame(27'h7fffff0,1);
        while(busy) begin @(negedge clk); test_ready=1; end
        if(error||received_words!=1) $fatal(1,"end-of-DDR boundary rejected");
        // Reset with an outstanding DDR read cancels both clients and stream.
        begin_frame(BASE,12);
        wait(cmd_valid&&cmd==3'b101); reset_all();
        if(busy||stream_valid||rsp_valid!=0) $fatal(1,"reset did not cancel");
        // Reset also cancels a final output beat held under stream backpressure.
        begin_frame(BASE,1);
        wait(stream_valid); reset_all();
        if(busy||stream_valid||rsp_valid!=0) $fatal(1,"held stream survived reset");

        // Saturated CPU read/write traffic, a long stalled CPU response, full
        // real-size scan timing and refresh. The FIFO budget is only 4 KiB.
        check_display=1;
        for(int frame=0;frame<3;frame++) begin
            int cpu_start;
            cpu_start=cpu_responses;
            begin_frame(BASE,FRAME_BURSTS);
            frame_words=0; min_level=FIFO_BURSTS;
            for(int pixel=0;pixel<1056*505;pixel++) begin
                int x,y;
                x=pixel%1056; y=pixel/1056;
                for(int phase=0;phase<3;phase++) begin
                    @(negedge clk);
                    urgent=fifo_level<224;
                    cpu_ready=!(frame==0 && pixel<1200);
                    cpu_valid=!outstanding[0];
                    cpu_addr=27'(((cpu_accepts/2)%128)*16);
                    cpu_data=128'h0123456789abcdef_fedcba9876543210 ^ 128'(cpu_accepts);
                    cpu_strb=cpu_accepts%2==0 ? 16'h5a5a : 0;
                    if(phase==0) begin
                        pixel_ready=x>=216 && x<1016 && y>=24 && y<504 && ((x-216)%8)==0;
                        if(pixel_ready) begin
                            if(!fifo_valid) $fatal(1,"display underrun frame=%0d x=%0d y=%0d CPU=%0d DMA=%0d",frame,x,y,cpu_responses,dma_accepts);
                            if(received_words<FRAME_BURSTS && int'(fifo_level)<min_level) min_level=int'(fifo_level);
                            if(fifo_data!==pattern(BASE+27'(frame_words*16))) $fatal(1,"display stream mismatch");
                            frame_words++;
                        end
                        pixel_clk=1;
                    end else if(phase==1) begin pixel_clk=0; pixel_ready=0; end
                end
            end
            if(frame_words!=FRAME_BURSTS || received_words!=FRAME_BURSTS || fifo_level!=0 || fifo_valid || busy || error)
                $fatal(1,"frame counts/busy/error");
            if(cpu_responses-cpu_start<100) $fatal(1,"CPU starved");
            $display("display frame %0d PASS: bursts=%0d min_fifo=%0d CPU=%0d refresh=%0d",frame,frame_words,min_level,cpu_responses-cpu_start,refreshes);
        end
        $display("DDR display PASS: frame ordering, masks, refresh, CPU backpressure, range/error/reset");
        $finish;
    end
    initial begin #60000000; $fatal(1,"test timeout"); end
endmodule
