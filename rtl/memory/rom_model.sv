`timescale 1ns / 1ps

// Instruction ROM — 4 KB (1024 × 32-bit words), base address 0x0000
// Asynchronous read: instruction is available in the same cycle the PC changes.
// Returns NOP (0x00000013) when chip-enable is low.
module rom_model (
    input  logic [31:0] addr, // Address from CPU
    input  logic        en,   // Chip enable
    output logic [31:0] rd_data
);

    logic [31:0] mem [0:1023]; // 4KB ROM

    // Combinational read — no clock edge needed; addr[11:2] selects the word
    assign rd_data = (en) ? mem[addr[11:2]] : 32'h00000013; // Return NOP if disabled

endmodule