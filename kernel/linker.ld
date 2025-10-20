ENTRY(_start)
OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)

SECTIONS
{
    /* Link the kernel in the higher half as required by Limine */
    . = 0xffffffff80000000;

    /* Place stivale2 header at the very beginning */
    .stivale2hdr : ALIGN(16)
    {
        KEEP(*(.stivale2hdr))
    }

    /* Also expose native limine header section */
    .liminehdr : ALIGN(16)
    {
        KEEP(*(.liminehdr))
    }

    .text : ALIGN(4096)
    {
        *(.text .text.*)
    }

    .rodata : ALIGN(4096)
    {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(4096)
    {
        *(.data .data.*)
    }

    .bss : ALIGN(4096)
    {
        *(COMMON)
        *(.bss .bss.*)
    }
}


