# memory test 


main: 

    li t0, 0x2000  # t0 = 0x2000 (some arbitrary memory address)
    li t1, 0x1000 # t1 = 0x1000 (GPIO base address) — load once

    li t2 , 0x88 
    sw t2, 0(t0) # write t2 to memory address in t1 (0x2000)
    mv t2, x0     # clear t2 to 0
    lw t3, 0(t0) # read from memory address in t1 (0x2000) into t2
    sw t3, 0(t1) # write t3 to memory address in t0 (0x1000)

    done:
        j done  # infinite loop to end the program

