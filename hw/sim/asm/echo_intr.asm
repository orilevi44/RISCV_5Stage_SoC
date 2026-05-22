# -----------------------------------------------------------------------------
# OS Level Interrupt Handler & UART Echo
# -----------------------------------------------------------------------------

main:
    # 1. Setup the Interrupt Vector (Where should the CPU jump?)
    li t0, 0x20           # 0x20 is the memory address of 'isr_vector' below
    csrw 0x305, t0        # Write 0x20 into mtvec (Machine Trap Vector)

    # 2. Enable Global Interrupts in CPU Core
    li t1, 8              # Bit 3 is MIE (Machine Interrupt Enable)
    csrw 0x300, t1        # Write 8 into mstatus

    # 3. Configure the PIC (Programmable Interrupt Controller)
    li t3, 0x4000         # Base address of PIC
    li t4, 1              # We want to enable Bit 0 (UART RX Interrupt)
    sw t4, 4(t3)          # Write 1 to PIC IRQ_ENABLE register (offset 0x4)

loop:
    # 4. Idle Loop (CPU waits here, saving power or running other threads)
    j loop


# -----------------------------------------------------------------------------
# Interrupt Service Routine (ISR)
# Starts at exactly PC = 0x20
# -----------------------------------------------------------------------------
isr_vector:
    # 5. Check WHO interrupted us by reading PIC IRQ_PENDING (offset 0x0)
    li t3, 0x4000         
    lw t4, 0(t3)          # Read pending interrupts into t4
    andi t4, t4, 1        # Isolate bit 0 (UART RX)
    beq t4, x0, end_isr   # If it's NOT the UART, skip and return

    # 6. Handle UART RX (Read byte and Echo it back)
    li t0, 0x3000         # UART base address
    lw t2, 0(t0)          # Reading UART drops rx_valid_sticky (Clears the IRQ!)
    sw t2, 0(t0)          # Echo the byte back to TX
    
    # 7. Hardware latency protection for TX PHY
    nop
    nop
    nop

wait_tx:
    # 8. Wait for TX to finish transmitting before returning
    lw t5, 4(t0)          # Read UART status
    nop
    andi t5, t5, 2        # Check tx_busy (bit 1)
    bne t5, x0, wait_tx   # If busy, keep waiting

end_isr:
    # 9. Return from interrupt (Restore PC and MIE)
    mret