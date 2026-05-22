#ALU Branch Test 

main: 
    lui t0, 0x1        # t0 = 0x1000 (GPIO base address) — load once

    # ==========================================
    # Test 1: BLT (Branch if Less Than) - FALSE
    # ==========================================

    li t1, 5          # t1 = 5
    li t2, 3          # t2 = 3
    blt t1, t2, trap_fail # if t1 < t2 then jump to trap_fail (should not happen)
    
    ## if we reach here, it means t1 is not less than t2, so we write t2 to GPIO
    sw t2, 0(t0)  # write t2 to GPIO (0x1000) if t1 is not less than t2        

    # ==========================================
    # Test 2: BEQ (Branch if Equal) - TRUE
    # ==========================================

    li t1, 5     # t1 =    5
    li t2, 5     # t2 =    5
    beq t1,t2 , beq_pass       # if t1 == t2 then jump to beq_pass (should happen)

    # If we are here, BEQ failed to jump! CPU has a bug.
    j trap_fail

    beq_pass:
        sw t1, 0(t0) # write t1 to GPIO (0x1000) to indicate BEQ passed
        j done    # infinite loop to end the program    

    trap_fail:
        li t6 , 0X99
        sw t6, 0(t0) # write 0x99 to GPIO (0x1000) to indicate failure
    trap_loop:
        j trap_loop  # infinite loop to indicate failure

    done:
        j done  # infinite loop to end the program




