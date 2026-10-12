// Wiring-only test top: the synthesizable CPU, CDC and cache remain Veryl.
module tb_tang_cached_boot #(parameter int WITH_IO=0, WITH_SD=0) (
    input logic i_cpu_clk, i_mem_clk, i_reset, i_enable, i_uart_rx,
    output logic o_uart_tx, o_shutdown,
    output logic [31:0] o_exit_code,
    output logic o_display_enable,
    input logic [1:0] i_display_error,
    output logic o_req_valid,
    input logic i_req_ready,
    output logic [26:0] o_req_addr,
    output logic [127:0] o_req_wdata,
    output logic [15:0] o_req_wstrb,
    input logic i_rsp_valid,
    output logic o_rsp_ready,
    input logic [127:0] i_rsp_data,
    input logic i_rsp_error,
    input logic sd_miso,
    output logic sd_cs_n, sd_sclk, sd_mosi
);
    wire req_valid, req_ready, rsp_valid, rsp_ready, rsp_error;
    wire [26:0] req_addr;
    wire [127:0] req_data, rsp_data;
    wire [15:0] req_strb;
    wire io_sel;
    wire [31:0] io_addr, io_wdata, io_rdata;
    wire [3:0] io_wstrb;
    if (WITH_SD) begin
        rv32ima_SdSpiMmio sd (.i_clk(i_cpu_clk), .i_reset,
            .i_sel(io_sel && io_addr[31:8]==24'h114000), .i_addr(io_addr[7:0]),
            .i_wdata(io_wdata), .i_wstrb(io_wstrb), .o_rdata(io_rdata),
            .o_cs_n(sd_cs_n), .o_sclk(sd_sclk), .o_mosi(sd_mosi), .i_miso(sd_miso));
    end else begin
        assign io_rdata=0;
        assign sd_cs_n=1;
        assign sd_sclk=0;
        assign sd_mosi=1;
    end
    rv32ima_DdrLinuxSoc #(.WITH_LCD(1), .WITH_IO(WITH_IO), .ROM_WORDS(WITH_SD?2048:1024),
        .PMP_ENTRIES(WITH_SD?2:4),
        .ROM_INIT(WITH_SD?"sim/tang_boot_standalone.hex":"sim/tang_boot_lcd.hex")) cpu (
        .i_cpu_clk, .i_mem_clk, .i_reset, .i_enable, .i_uart_rx,
        .o_uart_tx, .o_shutdown, .o_exit_code, .o_display_enable, .i_display_error,
        .i_io_rdata(io_rdata), .o_io_sel(io_sel), .o_io_addr(io_addr), .o_io_wdata(io_wdata), .o_io_wstrb(io_wstrb),
        .o_req_valid(req_valid), .i_req_ready(req_ready), .o_req_addr(req_addr),
        .o_req_wdata(req_data), .o_req_wstrb(req_strb), .i_rsp_valid(rsp_valid),
        .o_rsp_ready(rsp_ready), .i_rsp_data(rsp_data), .i_rsp_error(rsp_error)
    );
    rv32ima_DdrBurstReadCache cache (
        .i_clk(i_mem_clk), .i_rst(i_reset), .i_req_valid(req_valid), .o_req_ready(req_ready),
        .i_req_addr(req_addr), .i_req_data(req_data), .i_req_strb(req_strb),
        .o_rsp_valid(rsp_valid), .i_rsp_ready(rsp_ready), .o_rsp_data(rsp_data), .o_rsp_error(rsp_error),
        .o_mem_valid(o_req_valid), .i_mem_ready(i_req_ready), .o_mem_addr(o_req_addr),
        .o_mem_data(o_req_wdata), .o_mem_strb(o_req_wstrb), .i_mem_rsp_valid(i_rsp_valid),
        .o_mem_rsp_ready(o_rsp_ready), .i_mem_rsp_data(i_rsp_data), .i_mem_rsp_error(i_rsp_error)
    );
endmodule
