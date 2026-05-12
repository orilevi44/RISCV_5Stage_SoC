`timescale 1ns / 1ps

// System Bus — address decoder for the SoC data bus.
// Routes CPU read/write to the correct peripheral based on address.
// Peripheral selects are asserted on address match alone (not gated on re/we).
//
// Bug fix note: the original code gated uart_sel/gpio_sel/ram_sel on (we || re).
// During a load-use bubble the hazard unit zeroes re for one cycle, so uart_sel
// would drop and the UART wrapper would return 0 instead of the real status.
// Fix: assert sel purely on address decode; each peripheral gates its own output.
module system_bus (
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic        re,
    output logic [31:0] rdata,
    output logic        rom_sel,
    input  logic [31:0] rom_rdata,
    output logic        ram_sel,
    output logic        ram_we,
    input  logic [31:0] ram_rdata,
    output logic        gpio_sel,
    output logic        gpio_we,
    input  logic [31:0] gpio_rdata,
    output logic        uart_sel,
    output logic        uart_we,
    input  logic [31:0] uart_rdata
);

    always_comb begin
        rom_sel  = 1'b0; ram_sel  = 1'b0; ram_we   = 1'b0;
        gpio_sel = 1'b0; gpio_we  = 1'b0; uart_sel = 1'b0;
        uart_we  = 1'b0; rdata    = 32'b0;

        // ROM Decoding
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_0FFF) begin
            rom_sel = 1'b1;
            rdata   = rom_rdata;
        end
        // GPIO Decoding — sel asserted on address match, not gated on re/we
        else if (addr == 32'h0000_1000) begin
            gpio_sel = 1'b1;   // FIX: was (we || re)
            gpio_we  = we;
            rdata    = gpio_rdata;
        end
        // RAM Decoding — sel asserted on address match, not gated on re/we
        else if (addr >= 32'h0000_2000 && addr <= 32'h0000_2FFF) begin
            ram_sel = 1'b1;    // FIX: was (we || re)
            ram_we  = we;
            rdata   = ram_rdata;
        end
        // UART Decoding — sel asserted on address match, not gated on re/we
        else if (addr >= 32'h0000_3000 && addr <= 32'h0000_300F) begin
            uart_sel = 1'b1;   // FIX: was (we || re)
            uart_we  = we;
            rdata    = uart_rdata ;
        end
    end

endmodule