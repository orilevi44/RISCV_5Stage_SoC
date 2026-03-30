/**
 * System Bus Interconnect
 * Purpose: Decodes the CPU address and routes data/control signals 
 * to the appropriate peripheral (ROM, RAM, GPIO, or UART).
 */
`timescale 1ns / 1ps

module system_bus (
    // Interface with RISC-V Core
    input  logic [31:0] addr,       // Address from CPU
    input  logic [31:0] wdata,      // Data to be written
    input  logic        we,         // Master Write Enable from CPU
    output logic [31:0] rdata,      // Multiplexed read data back to CPU

    // ROM (Instruction Memory: 0x0000 - 0x0FFF)
    output logic        rom_sel,
    input  logic [31:0] rom_rdata,

    // RAM (Data Memory: 0x2000 - 0x2FFF)
    output logic        ram_sel,
    output logic        ram_we,     // Gated WE for RAM
    input  logic [31:0] ram_rdata,

    // GPIO (Peripheral: 0x1000)
    output logic        gpio_sel,
    output logic        gpio_we,    // Gated WE for GPIO
    input  logic [31:0] gpio_rdata,
    
    // UART (Peripheral: 0x3000 - 0x300F)
    output logic        uart_sel,
    output logic        uart_we,    // Gated WE for UART
    input  logic [31:0] uart_rdata
);

    /**
     * Address Decoding Logic
     * Routes signals based on the defined Memory Map.
     */
    always_comb begin
        // Default values to prevent latches and unintended writes
        rom_sel  = 1'b0;
        ram_sel  = 1'b0;
        ram_we   = 1'b0;
        gpio_sel = 1'b0;
        gpio_we  = 1'b0;
        uart_sel = 1'b0; 
        uart_we  = 1'b0;
        rdata    = 32'b0;

        // --- ROM Decoding (0x0000_0000 - 0x0000_0FFF) ---
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_0FFF) begin
            rom_sel = 1'b1;
            rdata   = rom_rdata;
        end
        
        // --- GPIO Decoding (Exactly 0x0000_1000) ---
        else if (addr == 32'h0000_1000) begin
            gpio_sel = 1'b1;
            gpio_we  = we; // Only allow write if address matches
            rdata    = gpio_rdata;
        end
        
        // --- RAM Decoding (0x0000_2000 - 0x0000_2FFF) ---
        else if (addr >= 32'h0000_2000 && addr <= 32'h0000_2FFF) begin
            ram_sel = 1'b1;
            ram_we  = we; 
            rdata   = ram_rdata;
        end
        
        // --- UART Decoding (0x0000_3000 - 0x0000_300F) ---
        else if (addr >= 32'h0000_3000 && addr <= 32'h0000_300F) begin
            uart_sel = 1'b1;
            uart_we  = we;
            rdata    = uart_rdata; 
        end
    end

endmodule