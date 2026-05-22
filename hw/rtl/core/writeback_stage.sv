`timescale 1ns / 1ps

/**
 * Writeback Stage
 * ---------------
 * Selects between the ALU result and the Memory read data to determine 
 * what value is written back to the destination register (rd).
 */
module writeback_stage (
    // --- Data Inputs ---
    input  logic [31:0] wb_alu_res,         // Arithmetic result or Link address
    input  logic [31:0] wb_mem_data,        // Formatted data from RAM
    
    // --- Control Inputs ---
    input  logic        wb_mem_to_reg_sel,  // Selector: 1 for Memory, 0 for ALU
    
    // --- Output to Register File ---
    output logic [31:0] wb_final_data       // Value routed back to Decode stage
);

    /**
     * Mux Selection Logic:
     * - Loads (LB, LW, etc.) select wb_mem_data.
     * - ALU ops, AUIPC, and Jumps (JAL/JALR) select wb_alu_res.
     */
    assign wb_final_data = (wb_mem_to_reg_sel) ? wb_mem_data : wb_alu_res;

endmodule