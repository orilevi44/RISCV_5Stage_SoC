`timescale 1ns / 1ps

module system_bus (
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,        // Master Write Enable from CPU
    output logic [31:0] rdata,

    // ROM (0x0000 - 0x0FFF)
    output logic        rom_sel,
    input  logic [31:0] rom_rdata,

    // RAM (0x2000 - 0x2FFF)
    output logic        ram_sel,
    output logic        ram_we,    // Specific WE for RAM
    input  logic [31:0] ram_rdata,

    // GPIO (0x1000)
    output logic        gpio_sel,
    output logic        gpio_we,   // Specific WE for GPIO
    input  logic [31:0] gpio_rdata
);

    always_comb begin
        // Default values
        rom_sel  = 1'b0;
        ram_sel  = 1'b0;
        ram_we   = 1'b0;
        gpio_sel = 1'b0;
        gpio_we  = 1'b0;
        rdata    = 32'b0;

        // Address Decoding Logic
        // -----------------------
        // ROM: 0x0000 to 0x0FFF
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_0FFF) begin
            rom_sel = 1'b1;
            rdata   = rom_rdata;
        end
        // GPIO: Exactly 0x0000_1000
        else if (addr == 32'h0000_1000) begin
            gpio_sel = 1'b1;
            gpio_we  = we; // Pass WE only if address matches
            rdata    = gpio_rdata;
        end
        // RAM: 0x0000_2000 to 0x0000_2FFF
        else if (addr >= 32'h0000_2000 && addr <= 32'h0000_2FFF) begin
            ram_sel = 1'b1;
            ram_we  = we;  // Pass WE only if address matches
            rdata   = ram_rdata;
        end
    end
endmodule