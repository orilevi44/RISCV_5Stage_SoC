MEMORY {
    rom (rx) : ORIGIN = 0x0000, LENGTH = 4K
    ram (rw) : ORIGIN = 0x2000, LENGTH = 4K
}

SECTIONS {
    /* אזור הקוד (פקודות לביצוע) */
    .text : {
        *(.text.init)
        *(.text*)
    } > rom

    /* אזור המשתנים הגלובליים */
    .data : { *(.data*) } > ram
    .bss  : { *(.bss*)  } > ram
}