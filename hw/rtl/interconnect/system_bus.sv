`timescale 1ns / 1ps

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
    input  logic [31:0] uart_rdata,

    input  logic  [3:0] data_byte_en, // <-- NEW: Byte Enable for RAM Writes
    output logic  [3:0] ram_byte_en,  // <-- NEW: Byte Enable Output to RAM
    // --- NEW: PIC Interface ---
    output logic        pic_sel,
    output logic        pic_we,
    input  logic [31:0] pic_rdata
);

    always_comb begin
        rom_sel  = 1'b0; ram_sel  = 1'b0; ram_we   = 1'b0;
        gpio_sel = 1'b0; gpio_we  = 1'b0; uart_sel = 1'b0;
        uart_we  = 1'b0; pic_sel  = 1'b0; pic_we   = 1'b0;
        rdata    = 32'b0;
        ram_byte_en = 4'b0; // Default: No bytes enabled

        // ROM Decoding
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_0FFF) begin
            rom_sel = 1'b1;
            rdata   = rom_rdata;
        end
        // GPIO Decoding 
        else if (addr == 32'h0000_1000) begin
            gpio_sel = 1'b1;   
            gpio_we  = we;
            rdata    = gpio_rdata;
        end
        // RAM Decoding 
        else if (addr >= 32'h0000_2000 && addr <= 32'h0000_2FFF) begin
            ram_sel = 1'b1;    
            ram_we  = we;
            rdata   = ram_rdata;
            ram_byte_en = data_byte_en; // Pass through byte enable for ROM (if needed)
        end
        // UART Decoding 
        else if (addr >= 32'h0000_3000 && addr <= 32'h0000_300F) begin
            uart_sel = 1'b1;   
            uart_we  = we;
            rdata    = uart_rdata ;
        end
        // PIC Decoding  
        else if (addr >= 32'h0000_4000 && addr <= 32'h0000_400F) begin
            pic_sel = 1'b1;
            pic_we  = we;
            rdata   = pic_rdata;
        end
    end

endmodule