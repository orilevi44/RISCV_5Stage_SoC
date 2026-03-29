/**
 * Instruction ROM Module - Asynchronous Read
 * This matches the timing expected by the RISC-V Pipeline.
 */
module rom_model (
    input  logic [31:0] addr, // Address from CPU
    input  logic        en,   // Chip enable
    output logic [31:0] rd_data
);

    logic [31:0] mem [0:1023]; // 4KB ROM

    // Asynchronous Read: No 'always_ff' here!
    // This ensures that as soon as the PC changes, 
    // the instruction is ready for the Fetch stage.
    assign rd_data = (en) ? mem[addr[11:2]] : 32'h00000013; // Return NOP if disabled

endmodule