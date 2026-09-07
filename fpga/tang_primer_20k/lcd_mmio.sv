// Board-local MMIO: staged drawing parameters, committed at frame start.
// Bundled-data CDC: mailbox is held from request until synchronized ack.
// Both domains must reset together; the wrapper enforces this on PLL unlock.
module TangLcdMmio (
    input wire i_cpu_clk, i_cpu_rst,
    input wire i_sel,
    input wire [31:0] i_addr, i_wdata,
    input wire [3:0] i_wstrb,
    output reg [31:0] o_rdata,
    input wire i_pixel_clk, i_pixel_rst, i_frame,
    output reg [223:0] o_config
);
    reg [31:0] stage [0:6];
    reg [223:0] mailbox;
    reg request, acknowledge;
    (* async_reg = "true" *) reg [1:0] ack_sync, req_sync;
    wire hit = i_sel && i_addr[31:8] == 24'h120000;
    wire busy = i_cpu_rst || (request != ack_sync[1]);
    wire [5:0] word_addr = i_addr[7:2];
    wire [31:0] byte_mask = {{8{i_wstrb[3]}}, {8{i_wstrb[2]}},
                              {8{i_wstrb[1]}}, {8{i_wstrb[0]}}};
    function automatic [31:0] register_mask(input [5:0] index);
        case (index)
            0: register_mask = 32'h1;
            1,2: register_mask = 32'hffff;
            3,5: register_mask = 32'h3ff;
            4,6: register_mask = 32'h1ff;
            default: register_mask = 0;
        endcase
    endfunction
    always @* begin
        o_rdata = 0;
        if (hit) begin
            case (word_addr)
                0,1,2,3,4,5,6: o_rdata = stage[word_addr[2:0]];
                7: o_rdata = {31'b0, busy};
                8: o_rdata = 32'h4c434431; // LCD1
                default: o_rdata = 0;
            endcase
        end
    end
    always @(posedge i_cpu_clk) begin
        if (i_cpu_rst) begin
            for (integer k=0; k<7; k=k+1) stage[k] <= (k == 0) ? 32'd1 : 32'd0;
            mailbox <= 224'd1;
            request <= 0;
            ack_sync <= 0;
        end else begin
            ack_sync <= {ack_sync[0], acknowledge};
            if (hit && |i_wstrb) begin
                if (word_addr < 7)
                    stage[word_addr[2:0]] <= ((stage[word_addr[2:0]] & ~byte_mask) |
                                        (i_wdata & byte_mask)) & register_mask(word_addr);
                // A busy commit is ignored; staged writes remain permitted.
                if (word_addr == 7 && i_wstrb[0] && i_wdata[0] && !busy) begin
                    mailbox <= {stage[6],stage[5],stage[4],stage[3],stage[2],stage[1],stage[0]};
                    request <= ~request;
                end
            end
        end
    end
    always @(posedge i_pixel_clk) begin
        if (i_pixel_rst) begin
            req_sync <= 0;
            acknowledge <= 0;
            o_config <= 224'd1;
        end else begin
            req_sync <= {req_sync[0], request};
            if (i_frame && req_sync[1] != acknowledge) begin
                o_config <= mailbox;
                acknowledge <= req_sync[1];
            end
        end
    end
endmodule
