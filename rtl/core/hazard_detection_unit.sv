`timescale 1ns / 1ps

/**
 * Hazard Detection Unit
 * ---------------------
 * Manages pipeline stalls (for Load-Use hazards) and flushes (for Control hazards).
 * * Stall: Freezes PC and IF/ID, inserts NOP into EX.
 * Flush: Clears pipeline registers when a branch is taken.
 */
module hazard_detection_unit (
    input  logic [4:0] id_rs1,           // rs1 from Decode stage
    input  logic [4:0] id_rs2,           // rs2 from Decode stage
    input  logic [4:0] ex_rd_addr,       // rd from Execute stage
    input  logic       ex_mem_read_en,   // High if EX instruction is a LOAD
    input  logic       jump_branch_taken,// High if Branch/Jump resolved in MEM stage
    
    // Control outputs to pipeline registers
    output logic       if_pc_en,         // 1 = update PC, 0 = freeze PC (Stall)
    output logic       id_reg_en,        // 1 = update IF/ID, 0 = freeze IF/ID (Stall)
    output logic       id_ex_flush,      // 1 = clear ID/EX (Stall or Branch taken)
    output logic       if_id_flush,      // 1 = clear IF/ID (Branch taken)
    output logic       ex_mem_flush      // 1 = clear EX/MEM (Branch taken)
);

    always_comb begin
        // Default: Pipeline flows normally
        if_pc_en     = 1'b1;
        id_reg_en    = 1'b1;
        id_ex_flush  = 1'b0;
        if_id_flush  = 1'b0;
        ex_mem_flush = 1'b0;

        /**
         * 1. Load-Use Hazard Detection
         * Occurs when a LOAD is in EX and the next instruction in ID needs the data.
         * Since RAM data isn't available until the end of MEM, we must stall for 1 cycle.
         */
        if (ex_mem_read_en && ((ex_rd_addr == id_rs1) || (ex_rd_addr == id_rs2))) begin
            if_pc_en    = 1'b0; // Freeze Fetch
            id_reg_en   = 1'b0; // Freeze Decode
            id_ex_flush = 1'b1; // Insert Bubble (NOP) into Execute
        end

        /**
         * 2. Control Hazard (Branch/Jump Taken)
         * Since our branch resolves in the MEM stage, if a branch is taken, 
         * the instructions in IF, ID, and EX stages are invalid and must be flushed.
         */
        if (jump_branch_taken) begin
            if_id_flush  = 1'b1; // Clear IF/ID register
            id_ex_flush  = 1'b1; // Clear ID/EX register
            ex_mem_flush = 1'b1; // Clear EX/MEM register
        end
    end

endmodule