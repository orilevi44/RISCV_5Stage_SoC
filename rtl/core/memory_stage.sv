`timescale 1ns / 1ps

/**
 * Memory Stage
 * Handles Data Memory (RAM) access and final branch decision logic.
 */
module memory_stage (
    // --- Data and Control Inputs from Register ---
    input  logic [31:0] mem_alu_result,     // Used as RAM Address
    input  logic [31:0] mem_write_data,     // Data to store in RAM (rs2)
    input  logic        mem_mem_read_en,    // Enable signal for reading RAM
    input  logic        mem_mem_write_en,   // Enable signal for writing RAM
    input  logic        mem_branch_en,      // High if instruction is a Branch
    input  logic        mem_alu_zero,       // Zero flag from ALU
    input  logic [2:0]  mem_funct3,         // To distinguish between BEQ, BNE, etc.
    
    // --- Data Memory (RAM) Interface ---
    output logic [31:0] ram_addr,           // Address sent to RAM
    output logic [31:0] ram_wr_data,        // Data to be written (din)
    output logic        ram_wr_en,          // Write enable (we)
    input  logic [31:0] ram_rd_data,        // Data read from RAM (dout)
    
    // --- Outputs to the rest of the CPU ---
    output logic [31:0] mem_read_data,      // Data passed to Writeback stage
    output logic        mem_branch_taken    // High if PC should jump to target
);

    /**
     * Branch Logic
     * Determines if a conditional branch should be taken based on the ALU zero flag.
     */
    always_comb begin
        case (mem_funct3)
            3'b000:  mem_branch_taken = mem_branch_en && mem_alu_zero;  // BEQ (Branch if Equal)
            3'b001:  mem_branch_taken = mem_branch_en && !mem_alu_zero; // BNE (Branch if Not Equal)
            // Note: You can add BLT, BGE here in the future
            default: mem_branch_taken = 1'b0;
        endcase
    end

    // --- RAM Interface Mapping ---
    assign ram_addr      = mem_alu_result;   // ALU result is the effective address
    assign ram_wr_data   = mem_write_data;   // Store the forwarded rs2 value
    assign ram_wr_en     = mem_mem_write_en; // Direct control from main unit
    
    // --- Outputs ---
    assign mem_read_data = ram_rd_data;      // Send raw RAM output to WB stage

endmodule