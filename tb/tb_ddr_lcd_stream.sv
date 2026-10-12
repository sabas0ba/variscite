// End-to-end scanout with the real controller and independent clock edges.
// SV models external DDR lane returns and checks each physical LCD pixel.
module tb_ddr_lcd_stream;
    localparam logic [26:0] BASE=27'h7c00000;
    logic mem_clk=0, pixel_clk=0, rst=1, enable=0;
    always #5 mem_clk=~mem_clk;
    initial begin #2; forever #15 pixel_clk=~pixel_clk; end
    wire dma_valid, dma_ready, urgent, memory_error, frame, hs, vs, de;
    wire [26:0] dma_addr;
    wire [8:0] level;
    wire [15:0] rgb;
    wire [31:0] underflows;
    wire [1:0] req_ready, rsp_valid, rsp_error;
    wire [127:0] rsp_data[2];
    wire [26:0] req_addr[2];
    wire [127:0] req_data[2];
    wire [15:0] req_strb[2];
    wire mem_valid, mem_ready, mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
    wire [26:0] mem_addr;
    wire [127:0] mem_data, mem_rsp_data;
    wire [15:0] mem_strb;
    wire cmd_valid;
    wire [2:0] cmd, bank;
    wire [13:0] addr;
    logic [127:0] read_data=0, returning_data;
    logic [1:0] read_valid=0;
    assign req_addr[0]=0;
    assign req_addr[1]=dma_addr;
    assign req_data[0]=0;
    assign req_data[1]=0;
    assign req_strb[0]=0;
    assign req_strb[1]=0;
    rv32ima_DdrLcdStream display_path (
        .i_mem_clk(mem_clk),.i_pixel_clk(pixel_clk),.i_reset(rst),.i_enable(enable),
        .o_req_valid(dma_valid),.i_req_ready(req_ready[1]),.o_req_addr(dma_addr),
        .i_rsp_valid(rsp_valid[1]),.o_rsp_ready(dma_ready),.i_rsp_data(rsp_data[1]),.i_rsp_error(rsp_error[1]),
        .o_urgent(urgent),.o_level(level),.o_memory_error(memory_error),
        .o_frame(frame),.o_hs(hs),.o_vs(vs),.o_de(de),.o_rgb(rgb),.o_underflows(underflows)
    );
    rv32ima_DdrBurstArbiter arbiter (
        .i_clk(mem_clk),.i_rst(rst),.i_req_valid({dma_valid,enable}),.o_req_ready(req_ready),
        .i_req_addr(req_addr),.i_req_data(req_data),.i_req_strb(req_strb),
        .o_rsp_valid(rsp_valid),.i_rsp_ready({dma_ready,1'b1}),.o_rsp_data(rsp_data),.o_rsp_error(rsp_error),
        .i_display_urgent(urgent),.o_mem_valid(mem_valid),.i_mem_ready(mem_ready),
        .o_mem_addr(mem_addr),.o_mem_data(mem_data),.o_mem_strb(mem_strb),
        .i_mem_rsp_valid(mem_rsp_valid),.o_mem_rsp_ready(mem_rsp_ready),
        .i_mem_rsp_data(mem_rsp_data),.i_mem_rsp_error(mem_rsp_error)
    );
    rv32ima_DdrBurstController controller (
        .i_clk(mem_clk),.i_rst(rst),.i_enable(enable),.i_req_valid(mem_valid),.o_req_ready(mem_ready),
        .i_req_addr(mem_addr),.i_req_data(mem_data),.i_req_strb(mem_strb),
        .o_rsp_valid(mem_rsp_valid),.i_rsp_ready(mem_rsp_ready),.o_rsp_data(mem_rsp_data),.o_rsp_error(mem_rsp_error),
        .i_read_data(read_data),.i_read_valid(read_valid),.o_cmd_valid(cmd_valid),.o_cmd(cmd),.o_addr(addr),.o_bank(bank),
        .o_read(),.o_odt(),.o_data(),.o_mask(),.o_dq_enable(),.o_dqs_enable(),.o_dqs_pattern()
    );
    function automatic logic [127:0] pattern(input logic [26:0] address);
        for(int b=0;b<16;b++) pattern[b*8+:8]=8'((32'(address)>>4) ^ (32'(address)>>12) ^ (b*37));
    endfunction
    int cycles=0, last_ref=0, last_pre=-100, last_act=-100, pending=0;
    int row=0, active_bank=0, cpu_responses=0, refreshes=0, dma_burst=0, memory_frame=0;
    bit active=0;
    logic [26:0] accepted_addr;
    always @(posedge mem_clk) begin
        read_valid<=0;
        if(!rst) begin
            cycles++;
            if(enable && cycles-last_ref>315) $fatal(1,"refresh overdue");
            if(dma_valid&&req_ready[1]) begin
                if(dma_addr!==BASE+27'(dma_burst*16)) $fatal(1,"continuous frame address");
                dma_burst=(dma_burst+1)%48000;
            end
            if(rsp_valid[0]) begin
                if(rsp_error[0] || rsp_data[0]!==pattern(0)) $fatal(1,"CPU response");
                cpu_responses++;
            end
            if(mem_valid&&mem_ready) begin
                if(mem_strb!=0) $fatal(1,"unexpected write");
                accepted_addr=mem_addr;
            end
            if(pending!=0) begin
                if(pending==2) begin read_data<=returning_data; read_valid<=1; end
                if(pending==1) begin read_data<=returning_data; read_valid<=2; end
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
                    3'b101: begin
                        logic [26:0] address;
                        address=27'((active_bank<<24)|(row<<11)|(int'(addr)<<1));
                        if(!active || cycles-last_act<4 || address!==accepted_addr) $fatal(1,"DDR address/tRCD");
                        returning_data=pattern(address);
                        // Give each successive frame a distinct value to expose
                        // duplicated/skipped whole frames as well as bad pixels.
                        if(address>=BASE) begin
                            returning_data^={8{16'(memory_frame*16'h1357)}};
                            if(address==BASE+27'(47999*16)) memory_frame++;
                        end
                        pending=8;
                    end
                    3'b010: begin
                        if(!active) $fatal(1,"PRE without ACT");
                        active=0; last_pre=cycles;
                    end
                    default: $fatal(1,"unexpected DDR command");
                endcase
            end
        end
    end
    bit tracking=0;
    int raster=0, cycle=0, cpu_start=0, min_level=256;
    always @(posedge pixel_clk) if(!rst) begin
        bit expected_hs, expected_vs, expected_de;
        logic [15:0] expected_rgb;
        logic [127:0] burst;
        int x,y,index;
        if(frame) begin
            if(tracking && cycle!=0) $fatal(1,"frame period");
            tracking=1;
        end
        if(tracking) begin
            x=cycle%1056; y=cycle/1056;
            expected_hs=!(x<128); expected_vs=!(y<3);
            expected_de=x>=216 && x<1016 && y>=24 && y<504;
            index=(y-24)*800+x-216;
            expected_rgb=0;
            if(expected_de) begin
                burst=pattern(BASE+27'((index/8)*16));
                expected_rgb=burst[(index%8)*16+:16] ^ 16'(raster*16'h1357);
                if(int'(level)<min_level) min_level=int'(level);
            end
            #1;
            if(hs!==expected_hs || vs!==expected_vs || de!==expected_de || rgb!==expected_rgb)
                $fatal(1,"scanout frame=%0d x=%0d y=%0d rgb=%h expected=%h underflows=%0d",raster,x,y,rgb,expected_rgb,underflows);
            if(memory_error || underflows!=0) $fatal(1,"scanout status");
            cycle++;
            if(cycle==1056*505) begin
                if(cpu_responses-cpu_start<100 || refreshes==0) $fatal(1,"CPU/refresh progress");
                $display("LCD stream frame %0d PASS: pixels=384000 min_fifo=%0d CPU=%0d refresh=%0d",raster,min_level,cpu_responses-cpu_start,refreshes);
                cycle=0; raster++; cpu_start=cpu_responses; min_level=256;
                if(raster==3) begin
                    $display("LCD stream PASS: continuous DDR -> async FIFO -> RGB565, CPU contention, refresh");
                    $finish;
                end
            end
        end
    end
    initial begin repeat(4) @(negedge mem_clk); rst=0; enable=1; end
    initial begin #50000000; $fatal(1,"stream test timeout"); end
endmodule
