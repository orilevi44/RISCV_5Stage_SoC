# test for the forwarding logic in the ALU and the Hazard Detection Unit


main: 
    li t0, 0x1000  # t0 = 0x1000 (GPIO base address) — load once
    li t5, 0x2000  # t5 = 0x2000 (some arbitrary memory address)

    # ==========================================
    # Test 1: ADD with forwarding - TRUE
    # ==========================================

    li t1, 5          # t1 = 5
    li t2, 3          # t2 = 3
    add t3, t1, t2    # t3 = t1 + t2 (should be 8)
    sw t3, 0(t0)      # write t3 to GPIO (0x1000) to indicate the result of the addition

    # ==========================================
    # Test 2: SUB with forwarding - TRUE
    # ==========================================

    li t1, 10          # t1 = 10
    li t2, 4           # t2 = 4
    sub t4, t1, t2    # t4 = t1 - t2 (should be 6)
    sw t4, 0(t0)      # write t4 to GPIO (0x1000) to indicate the result of the subtraction

    # ==========================================
    # Test 3: Load and Use Hazard - TRUE
    # ==========================================

    sw t1, 0(t5)      # write t1 [t1 = 10] to memory address in t5 (0x2000)
    lw t6, 0(t5)      # read from memory address in t5 (0x2000) into t6 (should be 10)
    add t3, t6, t2    # t7 = t6 + t2 (should be 14)
    sw t3, 0(t0)      # write t7 to GPIO (0x1000) to indicate the result of the load and use hazard test

    done:
        j done  # infinite loop to end the program