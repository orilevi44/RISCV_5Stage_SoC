/**
 * UART Wrapper Module
 * -------------------
 * This module bridges the System Bus (Memory-Mapped I/O) to the UART Transmitter.
 * * Memory Map (Offsets from Base 0x3000):
 * - 0x0: Data Register (Write-Only) -> Writing here starts a transmission.
 * - 0x4: Status Register (Read-Only) -> Bit [0] indicates if UART is busy (1=Busy, 0=Idle).
 */
`timescale 1ns / 1ps

module uart_wrapper #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Interface to System Bus ---
    input  logic        sel,      // Chip Select (Active when address is in UART range)
    input  logic        we,       // Write Enable (Active during Store instructions)
    input  logic [31:0] addr,     // Full 32-bit Address
    input  logic [31:0] wdata,    // Write Data from CPU
    output logic [31:0] rdata,    // Read Data to CPU
    
    // --- External Physical Pin ---
    output logic        uart_txd  // Physical TX Line
);

    // Internal signals
    logic       tx_en;
    logic       tx_busy;
    logic [3:0] addr_offset;

    // Extract the lower 4 bits of the address for register selection
    assign addr_offset = addr[3:0];

    // 1. Instantiate the physical UART Transmitter (UART PHY)
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx_phy (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (wdata[7:0]), // Map lowest byte of word to UART data
        .tx_en    (tx_en),
        .tx_busy  (tx_busy),
        .uart_txd (uart_txd)
    );

    /**
     * Bus Interface Logic
     * Uses a case statement for cleaner address decoding,
     * resolving the "constant selects" simulation warning.
     */
    always_comb begin
        // Default values to avoid latches
        tx_en = 1'b0;
        rdata = 32'b0;
        
        if (sel) begin
            case (addr_offset)
                // Register 0x0: Data Transmission
                4'h0: begin
                    if (we) tx_en = 1'b1;
                end
                
                // Register 0x4: Status Check
                4'h4: begin
                    if (!we) rdata = {31'b0, tx_busy};
                end
                
                default: rdata = 32'b0;
            endcase
        end
    end

endmodule