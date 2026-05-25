`timescale 1ns / 1ps

/**
 * Immediate Generator
 * -------------------------------------------------------------------------
 * Parses the 32-bit instruction word and extracts/extends the immediate field 
 * into a full 32-bit value based on the RISC-V instruction format encoding.
 * * It handles the 'Sign Extension' by replicating the MSB (instr[31]) to fill 
 * the upper bits of the 32-bit word.
 */
module imm_gen (
    input  logic [31:0] instr,   // Raw 32-bit instruction
    output logic [31:0] imm      // Formatted 32-bit immediate value
);
    
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    // Pre-calculated immediate wires for all possible RISC-V formats
    logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;

    // --- Sign Extension and Field Assembly ---
    // I-Type: 12-bit immediate (Loads, ADDI)
    assign i_imm = {{20{instr[31]}}, instr[31:20]};
    
    // S-Type: 12-bit immediate split in two parts (Stores)
    assign s_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    
    // B-Type: 12-bit immediate split in multiple parts, shifted left by 1 (Branches)
    assign b_imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    
    // U-Type: 20-bit immediate placed in the upper 20 bits (LUI, AUIPC)
    assign u_imm = {instr[31:12], 12'b0};
    
    // J-Type: 20-bit immediate shuffled and shifted left by 1 (JAL)
    assign j_imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    // ==============================================================================
    // Immediate Multiplexer
    // ==============================================================================
    // Selects the correctly formatted immediate based on the instruction's opcode.
    always_comb begin
        case (opcode)
            // I-Type formats
            7'b0000011, 7'b0010011, 7'b1100111: imm = i_imm; 
            
            // S-Type format
            7'b0100011:                         imm = s_imm; 
            
            // B-Type format
            7'b1100011:                         imm = b_imm; 
            
            // U-Type formats
            7'b0110111, 7'b0010111:             imm = u_imm; 
            
            // J-Type format
            7'b1101111:                         imm = j_imm; 
            
            // Default to zero for R-Type or invalid opcodes
            default:                            imm = 32'b0;
        endcase
    end
endmodule