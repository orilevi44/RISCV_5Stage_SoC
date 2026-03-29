`timescale 1ns / 1ps

/**
 * Writeback Stage
 * Selects the final data to be written back to the Register File.
 */
module writeback_stage (
    // --- Data Inputs ---
    input  logic [31:0] wb_alu_res,         // Data from the ALU calculation
    input  logic [31:0] wb_mem_data,        // Data read from RAM (for Loads)
    
    // --- Control Inputs ---
    input  logic        wb_mem_to_reg_sel,  // 1 selects Memory, 0 selects ALU
    
    // --- Output to Register File ---
    output logic [31:0] wb_final_data       // Data sent back to the Decode stage
);

    /**
     * Data Selection Multiplexer
     * If it's a Load instruction (LW), we choose wb_mem_data.
     * Otherwise, we choose wb_alu_res (ADD, ADDI, JAL, etc.).
     */
    assign wb_final_data = (wb_mem_to_reg_sel) ? wb_mem_data : wb_alu_res;

endmodule