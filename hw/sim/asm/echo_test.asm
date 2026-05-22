# UART Echo Program
# Reads a byte from UART RX, then echoes it back via UART TX.
#
# PC Layout (5-stage pipeline NOPs inserted for load-use hazard):
#   0x00: lui  t0, 0x3           # t0 = 0x3000
#   0x04: lbu  t1, 4(t0)         # wait_rx: read status (0x3004)
#   0x08: nop                    # load delay slot
#   0x0C: andi t1, t1, 1         # isolate rx_valid (bit 0)
#   0x10: beqz t1, wait_rx       # BEQ x6,x0,-16 → 0x00 (lui, harmless)
#   0x14: lbu  t2, 0(t0)         # read RX data (0x3000), clears rx_valid_sticky
#   0x18: lbu  t1, 4(t0)         # wait_tx: read status (0x3004)
#   0x1C: nop                    # load delay slot
#   0x20: andi t1, t1, 2         # isolate tx_busy (bit 1)
#   0x24: bnez t1, wait_tx       # BNE x6,x0,-12 → 0x18  (fe031ae3)
#   0x28: sb   t2, 0(t0)         # transmit echo byte (0x3000)
#   0x2C: jal  x0, -40           # j wait_rx → 0x04

main:
    lui t0, 0x3

wait_rx:
    lbu t1, 4(t0)        # read UART status register (0x3004)
    nop                  # load-use delay slot
    andi t1, t1, 1       # check rx_valid (bit 0)
    beqz t1, wait_rx     # loop if no data yet

    lbu t2, 0(t0)        # read RX byte from 0x3000 (clears rx_valid_sticky)

wait_tx:
    lbu t1, 4(t0)        # read UART status register (0x3004)
    nop                  # load-use delay slot
    andi t1, t1, 2       # check tx_busy (bit 1)
    bnez t1, wait_tx     # loop while TX busy  ← BNE (fe031ae3), offset=-12→0x18

    sb t2, 0(t0)         # transmit echo byte to 0x3000
    j wait_rx            # wait for next character
