module tb_ddr_display_fifo #(
    parameter int MEM_HALF=5, PIXEL_HALF=15
);
    logic mem_clk=0, pixel_clk=0, rst=1, mem_run=1, pixel_run=1;
    always #(MEM_HALF) if(mem_run) mem_clk=~mem_clk; else mem_clk=0;
    always #(PIXEL_HALF) if(pixel_run) pixel_clk=~pixel_clk; else pixel_clk=0;
    logic valid=0, ready=0;
    wire write_ready, read_valid;
    wire [8:0] level;
    logic [127:0] data=0;
    wire [127:0] result;
    logic [127:0] expected[$];
    logic [127:0] held;
    bit was_held=0;
    int written=0, consumed=0, epoch=0, write_ticks=0, read_ticks=0;
    int mode=0;
    rv32ima_DdrDisplayFifo dut (
        .i_mem_clk(mem_clk),.i_pixel_clk(pixel_clk),.i_reset(rst),
        .i_valid(valid),.o_ready(write_ready),.i_data(data),.o_level(level),
        .o_valid(read_valid),.i_ready(ready),.o_data(result)
    );
    function automatic logic [127:0] pattern(input int sequence_number);
        return {32'(epoch),32'(sequence_number),32'(~sequence_number),32'(sequence_number*37)};
    endfunction
    always @(posedge rst) begin expected.delete(); written=0; consumed=0; was_held=0; end
    always @(negedge mem_clk) begin
        write_ticks++;
        valid=!rst && (mode==1 || (mode==3 && write_ticks%7<5));
        data=pattern(written);
    end
    always @(negedge pixel_clk) begin
        read_ticks++;
        ready=!rst && (mode==2 || (mode==3 && read_ticks%11<7));
    end
    always @(posedge mem_clk) if(!rst) begin
        if(level>256) $fatal(1,"invalid occupancy");
        if(valid&&write_ready) begin
            expected.push_back(data); written++;
            if(written-consumed>257) $fatal(1,"FIFO overrun");
        end
    end
    always @(posedge pixel_clk) if(!rst) begin
        if(was_held && (!read_valid || result!==held)) $fatal(1,"stalled data changed");
        was_held=read_valid&&!ready; held=result;
        if(read_valid&&ready) begin
            logic [127:0] value;
            if(expected.size()==0) $fatal(1,"duplicate/stale FIFO output");
            value=expected.pop_front();
            if(result!==value) $fatal(1,"FIFO order/data mismatch epoch=%0d count=%0d",epoch,consumed);
            consumed++;
        end
    end
    task automatic reset_fifo;
        mode=0; valid=0; ready=0; rst=1; epoch++;
        #(20*(MEM_HALF+PIXEL_HALF)); rst=0;
        #(20*(MEM_HALF+PIXEL_HALF));
    endtask
    task automatic fill_and_drain;
        mode=1;
        wait(written==257);
        repeat(30) @(negedge mem_clk);
        if(write_ready || level!=256 || written!=257 || !read_valid) $fatal(1,"full capacity/hold");
        mode=2;
        wait(consumed==written);
        repeat(10) @(negedge pixel_clk);
        if(read_valid || expected.size()!=0) $fatal(1,"empty FIFO");
        repeat(10) @(negedge mem_clk);
        if(!write_ready || level!=0) $fatal(1,"empty write domain");
    endtask
    initial begin
        reset_fifo(); fill_and_drain();
        mode=3;
        wait(consumed>=5000);
        mode=2;
        wait(consumed==written);
        repeat(10) @(negedge pixel_clk);
        if(read_valid || expected.size()!=0) $fatal(1,"random drain");
        // Reset a full FIFO while one clock is stopped; no old epoch may leak.
        reset_fifo(); mode=1; wait(written==257);
        @(negedge pixel_clk); pixel_run=0;
        reset_fifo();
        if(read_valid) $fatal(1,"reset did not assert with pixel clock stopped");
        pixel_run=1; fill_and_drain();
        reset_fifo(); mode=1; wait(written==257);
        @(negedge mem_clk); mem_run=0;
        reset_fifo();
        if(write_ready || read_valid) $fatal(1,"reset/release with memory clock stopped");
        mem_run=1; fill_and_drain();
        $display("display FIFO PASS: %0d/%0d clocks, full/empty, wrap, stalls, stopped-clock reset",MEM_HALF,PIXEL_HALF);
        $finish;
    end
    initial begin #2000000; $fatal(1,"FIFO test timeout"); end
endmodule
