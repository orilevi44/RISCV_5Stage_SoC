`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Hazard Detection Unit
//
// Handles four hazard classes:
//   1. Branch/jump flush  — flushes IF/ID, ID/EX, EX/MEM on a taken branch.
//   2. I-Cache Stall      — stalls PC and IF/ID, flushes ID/EX when I-Cache misses.
//   3. UART wait-state    — stalls the pipeline for UART sync.
//   4. Load-use stall     — stalls IF+ID and flushes ID/EX for data dependencies.
// ---------------------------------------------------------------------------

module hazard_detection_unit (
    // Load-use hazard inputs
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_mem_read_en,

    // Branch/jump taken
    input  logic        jump_branch_taken,

    // I-Cache Stall Input
    input  logic        icache_stall,

    // UART wait-state inputs
    input  logic        mem_mem_read_en,    
    input  logic [31:0] mem_alu_result,     
    input  logic        uart_already_waited,

    // Standard pipeline control outputs
    output logic        if_pc_en,
    output logic        id_reg_en,
    output logic        id_ex_flush,
    output logic        if_id_flush,
    output logic        ex_mem_flush,

    // UART wait-state output
    output logic        uart_stall
);

    // Detect a read whose target address falls in the UART window.
    logic uart_read_detected;
    assign uart_read_detected = mem_mem_read_en &&
                                (mem_alu_result[31:4] == 28'h0000_300);

    // Assert for exactly one cycle
    assign uart_stall = uart_read_detected && !uart_already_waited;

    // -----------------------------------------------------------------------
    // Priority (highest → lowest):
    //   1. jump_branch_taken — hard flush of fetch/decode/execute
    //   2. icache_stall      — freeze PC & Decode, inject NOP to Execute
    //   3. uart_stall        — freeze everything ahead of MEM
    //   4. load-use          — stall fetch/decode, flush ID/EX bubble
    // -----------------------------------------------------------------------
    always_comb begin
        // Defaults: pipeline flows freely
        if_pc_en     = 1'b1;
        id_reg_en    = 1'b1;
        id_ex_flush  = 1'b0;
        if_id_flush  = 1'b0;
        ex_mem_flush = 1'b0;

        if (jump_branch_taken) begin
            // Kill the three instructions speculatively fetched after the branch.
            if_id_flush  = 1'b1;
            id_ex_flush  = 1'b1;
            ex_mem_flush = 1'b1;
        end
        else if (icache_stall) begin 
            // I-Cache Miss: Freeze the PC so we don't skip instructions,
            // freeze ID so the current instruction isn't overwritten by garbage,
            // and flush ID/EX so a NOP goes down the pipe.
            if_pc_en     = 1'b0;
            id_reg_en    = 1'b0;
            id_ex_flush  = 1'b1;
        end
        else if (uart_stall) begin
            if_pc_en  = 1'b0;
            id_reg_en = 1'b0;
        end
        else if (ex_mem_read_en && (ex_rd_addr != 5'b0) &&
                 ((ex_rd_addr == id_rs1) || (ex_rd_addr == id_rs2))) begin
            // Classic load-use: stall fetch/decode, bubble decode/execute.
            if_pc_en    = 1'b0;
            id_reg_en   = 1'b0;
            id_ex_flush = 1'b1;
        end
    end

endmodule