///### AXI4 bus package prototype





package __std_axi4_config;

    typedef enum logic [3-1:0] {
        axsize_variants_BYTES_PER_TRANSFER_1 = $bits(logic [3-1:0])'(3'b000),
        axsize_variants_BYTES_PER_TRANSFER_2 = $bits(logic [3-1:0])'(3'b001),
        axsize_variants_BYTES_PER_TRANSFER_4 = $bits(logic [3-1:0])'(3'b010),
        axsize_variants_BYTES_PER_TRANSFER_8 = $bits(logic [3-1:0])'(3'b011),
        axsize_variants_BYTES_PER_TRANSFER_16 = $bits(logic [3-1:0])'(3'b100),
        axsize_variants_BYTES_PER_TRANSFER_32 = $bits(logic [3-1:0])'(3'b101),
        axsize_variants_BYTES_PER_TRANSFER_64 = $bits(logic [3-1:0])'(3'b110),
        axsize_variants_BYTES_PER_TRANSFER_128 = $bits(logic [3-1:0])'(3'b111)
    } axsize_variants;

    typedef enum logic [2-1:0] {
        axburst_variants_FIXED_BURST = $bits(logic [2-1:0])'(2'b00),
        axburst_variants_INCREMENTING_BURST = $bits(logic [2-1:0])'(2'b01),
        axburst_variants_WRAPPING_BURST = $bits(logic [2-1:0])'(2'b10)
    } axburst_variants;

    typedef struct packed {
        logic allocate      ;
        logic other_allocate;
        logic modifiable    ;
        logic bufferable    ;
    } awcache_bits;

    typedef struct packed {
        logic other_allocate;
        logic allocate      ;
        logic modifiable    ;
        logic bufferable    ;
    } arcache_bits;

    typedef struct packed {
        logic instruction_access;
        logic non_secure        ;
        logic privileged        ;
    } axprot_bits;

    typedef enum logic [2-1:0] {
        resp_variants_OKAY = $bits(logic [2-1:0])'(2'b00),
        resp_variants_EXOKAY = $bits(logic [2-1:0])'(2'b01),
        resp_variants_SLVERR = $bits(logic [2-1:0])'(2'b10),
        resp_variants_DECERR = $bits(logic [2-1:0])'(2'b11)
    } resp_variants;

endpackage

///### AXI4 bus package


package __std_axi3_config;

    typedef enum logic [3-1:0] {
        axsize_variants_BYTES_PER_TRANSFER_1 = $bits(logic [3-1:0])'(3'b000),
        axsize_variants_BYTES_PER_TRANSFER_2 = $bits(logic [3-1:0])'(3'b001),
        axsize_variants_BYTES_PER_TRANSFER_4 = $bits(logic [3-1:0])'(3'b010),
        axsize_variants_BYTES_PER_TRANSFER_8 = $bits(logic [3-1:0])'(3'b011),
        axsize_variants_BYTES_PER_TRANSFER_16 = $bits(logic [3-1:0])'(3'b100),
        axsize_variants_BYTES_PER_TRANSFER_32 = $bits(logic [3-1:0])'(3'b101),
        axsize_variants_BYTES_PER_TRANSFER_64 = $bits(logic [3-1:0])'(3'b110),
        axsize_variants_BYTES_PER_TRANSFER_128 = $bits(logic [3-1:0])'(3'b111)
    } axsize_variants;

    typedef enum logic [2-1:0] {
        axburst_variants_FIXED_BURST = $bits(logic [2-1:0])'(2'b00),
        axburst_variants_INCREMENTING_BURST = $bits(logic [2-1:0])'(2'b01),
        axburst_variants_WRAPPING_BURST = $bits(logic [2-1:0])'(2'b10)
    } axburst_variants;

    typedef struct packed {
        logic write_allocate;
        logic read_allocate ;
        logic cacheable     ;
        logic bufferable    ;
    } axcache_bits;

    typedef struct packed {
        logic instruction_access;
        logic non_secure        ;
        logic privileged        ;
    } axprot_bits;

    typedef enum logic [2-1:0] {
        resp_variants_OKAY = $bits(logic [2-1:0])'(2'b00),
        resp_variants_EXOKAY = $bits(logic [2-1:0])'(2'b01),
        resp_variants_SLVERR = $bits(logic [2-1:0])'(2'b10),
        resp_variants_DECERR = $bits(logic [2-1:0])'(2'b11)
    } resp_variants;

endpackage

///### AXI3 bus package


package __std_axi4_lite_config;

    typedef struct packed {
        logic instruction_access;
        logic non_secure        ;
        logic privileged        ;
    } axprot_bits;

    typedef enum logic [2-1:0] {
        resp_variants_OKAY = $bits(logic [2-1:0])'(2'b00),
        resp_variants_EXOKAY = $bits(logic [2-1:0])'(2'b01),
        resp_variants_SLVERR = $bits(logic [2-1:0])'(2'b10),
        resp_variants_DECERR = $bits(logic [2-1:0])'(2'b11)
    } resp_variants;

endpackage

///### AXI4-Lite bus package


//# sourceMappingURL=axi_pkg.sv.map
