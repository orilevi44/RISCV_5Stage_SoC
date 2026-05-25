`timescale 1ns / 1ps

/**
 * IF/ID Pipeline Register
 * -------------------------------------------------------------------------
 * This sequential element separates the Instruction Fetch (IF) stage from 
 * the Instruction Decode (ID) stage. It latches the Program Counter and the 
 * fetched instruction on every active clock edge.
 * * It fully supports pipeline control mechanisms:
 * - Stall: Freezes the current state (when 'en' is low).
 * - Flush: Invalidates the current instruction by injecting a NOP (bubble).
 */
module if_id_reg (
    // Global Clock and Reset
    input  logic        clk,
    input  logic        rst_n,      // Active-low asynchronous reset

    // Pipeline Control Signals
    input  logic        flush,      // Synchronous flush (1 = clear and insert NOP)
    input  logic        en,         // Enable signal (1 = latch new data, 0 = stall)

    // Inputs from Fetch Stage (IF)
    input  logic [31:0] if_pc,      // Program Counter from IF stage
    input  logic [31:0] if_inst,    // Instruction read from I-Cache/ROM

    // Outputs to Decode Stage (ID)
    output logic [31:0] id_pc,      // Latched Program Counter
    output logic [31:0] id_inst     // Latched Instruction
);

    // RISC-V Standard NOP: 'addi x0, x0, 0' (Machine code: 32'h00000013)
    localparam [31:0] NOP_INST = 32'h00000013;

    // ==============================================================================
    // Pipeline Register Logic
    // ==============================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 1. Asynchronous Reset: Clear pipeline state on startup
            id_pc   <= 32'b0;
            id_inst <= NOP_INST;
        end 
        else if (flush) begin
            // 2. Synchronous Flush: Triggered by control hazards (Branches/Jumps)
            // Replaces the incoming instruction with a harmless NOP bubble.
            id_pc   <= 32'b0;       // Optional: Zeroing PC during flush for cleaner waveforms
            id_inst <= NOP_INST;
        end 
        else if (en) begin
            // 3. Normal Operation: Advance the pipeline
            // Latch data from IF to ID.
            id_pc   <= if_pc;
            id_inst <= if_inst;
        end
        // Implicit Else: (en == 0) -> Pipeline Stall.
        // The flip-flops retain their current values, holding the instruction in ID.
    end

endmodule