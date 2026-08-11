/* Minimal flat layout for the FDPIC-loaded PIE init.
 * The ELF type is patched to ET_DYN after linking (bare-metal ld has no -pie).
 *
 * The base must be non-zero: binfmt_elf_fdpic skips entry-point relocation
 * when e_entry == 0 (fs/binfmt_elf_fdpic.c, "map the entry point"), which
 * would make the kernel jump to address 0. It is also page-aligned so the
 * segment's p_offset stays page-congruent for the NOMMU mmap.
 */
ENTRY(_start)
SECTIONS
{
    . = 0x1000;
    .text   : { *(.text*) }
    .rodata : { *(.rodata*) }
    .data   : { *(.data*) }
    .bss    : { *(.bss*) *(COMMON) }
}
