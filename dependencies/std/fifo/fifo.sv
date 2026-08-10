module __std_fifo #(
    parameter  int unsigned WIDTH             = 8                            ,
    parameter  type         TYPE              = logic [WIDTH-1:0]            ,
    parameter  int unsigned DEPTH             = 8                            ,
    parameter  int unsigned THRESHOLD         = DEPTH                        ,
    parameter  bit          FLAG_FF_OUT       = 1'b1                         ,
    parameter  bit          DATA_FF_OUT       = 1'b1                         ,
    parameter  bit          RESET_RAM         = 1'b0                         ,
    parameter  bit          RESET_DATA_FF     = 1'b1                         ,
    parameter  bit          CLEAR_DATA        = 1'b0                         ,
    parameter  bit          PUSH_ON_CLEAR     = 1'b0                         ,
    parameter  int unsigned MATCH_COUNT_WIDTH = 0                            ,
    localparam type         COUNTER           = logic [$clog2(DEPTH + 1)-1:0]
) (
    input  var logic   i_clk        ,
    input  var logic   i_rst        ,
    input  var logic   i_clear      ,
    output var logic   o_empty      ,
    output var logic   o_almost_full,
    output var logic   o_full       ,
    output var COUNTER o_word_count ,
    input  var logic   i_push       ,
    input  var TYPE    i_data       ,
    input  var logic   i_pop        ,
    output var TYPE    o_data   
);
    localparam int unsigned RAM_WORDS = ((DATA_FF_OUT) ? ( DEPTH - 1 ) : ( DEPTH ));

    logic clear_data;

    always_comb begin
        clear_data = CLEAR_DATA && i_clear;
    end

    //--------------------------------------------------------------
    //  controller
    //--------------------------------------------------------------
    localparam int unsigned RAM_POINTER_WIDTH = ((RAM_WORDS >= 2) ? ( $clog2(RAM_WORDS) ) : ( 1 ));

    logic [RAM_POINTER_WIDTH-1:0] write_pointer;
    logic                         write_to_ff  ;
    logic                         write_to_ram ;
    logic [RAM_POINTER_WIDTH-1:0] read_pointer ;
    logic                         read_from_ram;

    __std_fifo_controller #(
        .TYPE              (TYPE             ),
        .DEPTH             (DEPTH            ),
        .THRESHOLD         (THRESHOLD        ),
        .FLAG_FF_OUT       (FLAG_FF_OUT      ),
        .DATA_FF_OUT       (DATA_FF_OUT      ),
        .PUSH_ON_CLEAR     (PUSH_ON_CLEAR    ),
        .RAM_WORDS         (RAM_WORDS        ),
        .RAM_POINTER_WIDTH (RAM_POINTER_WIDTH),
        .MATCH_COUNT_WIDTH (MATCH_COUNT_WIDTH)
    ) u_controller (
        .i_clk           (i_clk        ),
        .i_rst           (i_rst        ),
        .i_clear         (i_clear      ),
        .o_empty         (o_empty      ),
        .o_almost_full   (o_almost_full),
        .o_full          (o_full       ),
        .i_push          (i_push       ),
        .i_data          (i_data       ),
        .i_pop           (i_pop        ),
        .o_word_count    (o_word_count ),
        .o_write_pointer (write_pointer),
        .o_write_to_ff   (write_to_ff  ),
        .o_write_to_ram  (write_to_ram ),
        .o_read_pointer  (read_pointer ),
        .o_read_from_ram (read_from_ram)
    );

    //--------------------------------------------------------------
    //  RAM
    //--------------------------------------------------------------
    TYPE ram_read_data;

    if (RAM_WORDS >= 1) begin :g_ram
        __std_ram #(
            .WORD_SIZE     (RAM_WORDS        ),
            .ADDRESS_WIDTH (RAM_POINTER_WIDTH),
            .DATA_TYPE     (TYPE             ),
            .BUFFER_OUT    (0                ),
            .USE_RESET     (RESET_RAM        )
        ) u_ram (
            .i_clk  (i_clk        ),
            .i_rst  (i_rst        ),
            .i_clr  (clear_data   ),
            .i_mea  ('1           ),
            .i_wea  (write_to_ram ),
            .i_adra (write_pointer),
            .i_da   (i_data       ),
            .i_meb  ('1           ),
            .i_adrb (read_pointer ),
            .o_qb   (ram_read_data)
        );
    end else begin :g_no_ram
        always_comb begin
            ram_read_data = TYPE'(0);
        end
    end

    //--------------------------------------------------------------
    //  output control
    //--------------------------------------------------------------
    if (DATA_FF_OUT) begin :g_data_out
        TYPE data_out;

        always_comb begin
            o_data = data_out;
        end

        if (RESET_DATA_FF) begin :g
            always_ff @ (posedge i_clk) begin
                if (i_rst) begin
                    data_out <= TYPE'(0);
                end else if (clear_data) begin
                    data_out <= TYPE'(0);
                end else if (write_to_ff) begin
                    data_out <= i_data;
                end else if (read_from_ram) begin
                    data_out <= ram_read_data;
                end
            end
        end else begin :g
            always_ff @ (posedge i_clk) begin
                if (clear_data) begin
                    data_out <= TYPE'(0);
                end else if (write_to_ff) begin
                    data_out <= i_data;
                end else if (read_from_ram) begin
                    data_out <= ram_read_data;
                end
            end
        end
    end else begin :g
        always_comb begin
            o_data = ram_read_data;
        end
    end
endmodule
//# sourceMappingURL=fifo.sv.map
