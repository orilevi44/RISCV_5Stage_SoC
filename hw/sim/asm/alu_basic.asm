# ALU Test

main:
    lui  t0, 0x1        # t0 = 0x1000 (GPIO base address) — load once

    # --- Test 1: ADD 5 + 3 = 8 ---
    addi x1, x0, 5
    addi x2, x0, 3
    add  x3, x1, x2
    sw   x3, 0(t0)
    nop
    nop

    # --- Test 2: SUB 5 - 3 = 2 ---
    sub  x3, x1, x2     # x1 and x2 still hold 5 and 3
    sw   x3, 0(t0)
    nop
    nop

    # --- Test 3: AND 5 & 3 = 1 ---
    and  x3, x1, x2
    sw   x3, 0(t0)
    nop
    nop

    # --- Test 4: OR  5 | 3 = 7 ---
    or   x3, x1, x2
    sw   x3, 0(t0)
    nop
    nop

done:
    j done              # stop here forever