`timescale 1ns / 1ps

/**
 * Fetch Stage (IF)
 * -------------------------------------------------------------------------
 * This module is responsible for retrieving the next instruction from the 
 * Instruction Memory (or Cache). It maintains the Program Counter (PC) and 
 * calculates the next PC based on sequential execution, stalls, or jumps.
 */
module fetch_stage (
    // Global Clock and Reset
    input  logic        clk,
    input  logic        rst_n,           // Active-low asynchronous reset

    // Control Signals (from Hazard Unit / Pipeline Control)
    input  logic        en,              // Pipeline enable signal (1 = Go, 0 = Stall)
    input  logic        jump_sel,        // Branch/Jump flag (1 = Branch Taken)
    input  logic [31:0] jump_addr,       // Target address for a taken branch/jump

    // Instruction Memory (ICache) Interface
    output logic [31:0] icache_addr,     // Address requested from Instruction Memory
    input  logic [31:0] icache_instr,    // Fetched instruction data
    input  logic        icache_ready,    // Memory readiness flag (1 = Data valid)

    // Pipeline Stage Outputs (to IF/ID Register)
    output logic [31:0] if_pc,           // Current PC value passed down the pipeline
    output logic [31:0] if_instr,        // Fetched instruction passed down the pipeline
    output logic        if_stall         // Output flag indicating a fetch stall
);

    // Internal wires for PC state
    logic [31:0] current_pc;
    logic [31:0] next_pc;

    // ==============================================================================
    // 1. Next PC Calculation Logic (Multiplexer)
    // ==============================================================================
    // Determines the target address for the next clock cycle.
    always_comb begin
        if (jump_sel) begin
            // Highest Priority: Control Hazard. A jump or branch was taken.
            next_pc = jump_addr;
        end else if (en) begin
            // Normal Execution: Advance PC by 4 bytes (32-bit instruction word).
            next_pc = current_pc + 32'd4;
        end else begin
            // Pipeline Stall: Maintain the current PC to re-fetch the same instruction.
            next_pc = current_pc;
        end
    end

    // ==============================================================================
    // 2. Control Logic
    // ==============================================================================
    logic pc_update_en;
    
    // The PC register is allowed to update if:
    // a) The Instruction Memory is ready AND the pipeline is not stalled.
    // b) A jump is taken (Overrides stalls to immediately redirect control flow).
    assign pc_update_en = (icache_ready && en) || jump_sel; 
    
    // Assert stall upwards if the memory is not ready to provide the instruction.
    assign if_stall     = !icache_ready;

    // ==============================================================================
    // 3. Program Counter Register Instance
    // ==============================================================================
    // Sequential element that holds the 32-bit PC value.
    pc_reg pc_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pc_update_en),
        .next_pc (next_pc),
        .pc_out  (current_pc)
    );

    // ==============================================================================
    // 4. Output Assignments
    // ==============================================================================
    assign icache_addr = current_pc;     // Drive memory address with current PC
    assign if_pc       = current_pc;     // Pass PC down the pipeline for address calculations
    assign if_instr    = icache_instr;   // Pass raw instruction word down the pipeline

endmodule