ENTRY(_start)

SECTIONS
{
    . = 0xffffffff80200000;

    .handover : ALIGN(4K)
    {
        KEEP(*(.handover*))
    }

    .text : ALIGN(4K)
    {
        *(.text*)
    }

    .rodata : ALIGN(4K)
    {
        __init_array_start = .;
        *(.ctors)
        *(.init_array)
        __init_array_end = .;

        __fini_array_start = .;
        *(.fini_array)
        *(.dtors)
        __fini_array_end = .;

        *(.rodata*)
    }

    .data : ALIGN(4K)
    {
        *(.data*)
    }

    .bss : ALIGN(4K)
    {
        *(COMMON)
        *(.bss*)
    }
}
