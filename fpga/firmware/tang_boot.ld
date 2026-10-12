ENTRY(_start)
SECTIONS {
    . = 0x1000;
    .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }
    .bss : { *(.bss .bss.*) *(COMMON) }
    ASSERT(SIZEOF(.text) <= ROM_BYTES, "boot ROM exceeds configured size")
    ASSERT(SIZEOF(.data) == 0 && SIZEOF(.bss) == 0, "boot ROM requires writable globals")
}
