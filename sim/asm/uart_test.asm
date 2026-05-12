# test for the uart 

main:
    li t0 , 0x3000   # load to t0 the uart address 
    
    # --- Transmit 'O' ---
    li t1 , 0x4F     # load to t1 the value of 'O' in ascii
    sw t1 , 0(t0)    # write the value of 'O' to the uart
    nop
    nop
    nop 
    
wait_tx1:
    lw t2 , 4(t0)    # read the value of the uart status register 0x3004
    nop
    andi t2 , t2 , 2 # isolate bit 1 (tx_busy)
    bne t2 , x0 , wait_tx1 # if tx_busy != 0, keep waiting 

    # --- Transmit 'K' ---
    li t1 , 0x4B     # load to t1 the value of 'K' in ascii
    sw t1 , 0(t0)    # write the value of 'K' to the uart

    nop
    nop
    nop 

wait_tx2: 
    lw t2 , 4(t0)    # read the value of the uart status register 0x3004
    nop
    andi t2 , t2 , 2 # isolate bit 1 (tx_busy)
    bne t2 , x0 , wait_tx2 # if tx_busy != 0, keep waiting 

done:
    j done