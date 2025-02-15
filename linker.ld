SECTIONS
{
    . = 0x00400000;

    .text : { *(.text) }
}

PHDRS
{
    text PT_LOAD FLAGS(7);
}

SECTIONS
{
    .text : { *(.text) } :text
}