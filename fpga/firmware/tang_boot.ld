ENTRY(_start)
SECTIONS {
    . = 0x1000;
    .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }
    .bss : { *(.bss .bss.*) *(COMMON) }
    ASSERT(SIZEOF(.text) <= 4096, "boot ROM exceeds 4 KiB")
    ASSERT(SIZEOF(.data) == 0 && SIZEOF(.bss) == 0, "boot ROM requires writable globals")
}
