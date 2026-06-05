`timescale 1ns / 1ps

/**
 * ============================================================================
 * Module      : forwarding_unit
 * Description : Data Hazard Resolution Unit for a 5-Stage RISC-V Pipeline.
 * This purely combinational unit implements data bypassing, 
 * allowing the EX stage to consume the most recent results 
 * directly from the MEM or WB stages before they are written 
 * back to the Register File.
 * ============================================================================
 */
module forwarding_unit (
    // --------------------------------------------------
    // Inputs from Execute Stage (EX)
    // --------------------------------------------------
    input  logic [4:0]  ex_rs1,           // Source Register 1 requested by ALU
    input  logic [4:0]  ex_rs2,           // Source Register 2 requested by ALU
    input  logic        ex_rs1_used,      // High if current EX instruction actually reads rs1
    input  logic        ex_rs2_used,      // High if current EX instruction actually reads rs2
    
    // --------------------------------------------------
    // Inputs from Memory Stage (MEM)
    // --------------------------------------------------
    input  logic [4:0]  mem_rd_addr,      // Destination register of the instruction in MEM
    input  logic        mem_reg_write_en, // High if MEM instruction writes to Register File
    
    // --------------------------------------------------
    // Inputs from Writeback Stage (WB)
    // --------------------------------------------------
    input  logic [4:0]  wb_rd_addr,       // Destination register of the instruction in WB
    input  logic        wb_reg_write_en,  // High if WB instruction writes to Register File
    
    // --------------------------------------------------
    // Forwarding Selection Outputs (To EX Stage Muxes)
    // --------------------------------------------------
    // 00: Default (Use value fetched from Register File)
    // 01: Forward from WB Stage
    // 10: Forward from MEM Stage
    output logic [1:0]  forward_a_sel,
    output logic [1:0]  forward_b_sel
);

    // ========================================================================
    // Forwarding Logic for Operand A (rs1)
    // ========================================================================
    always_comb begin
        // Priority 1: MEM Hazard (Most recent data)
        // If the instruction immediately preceding the current one modifies rs1.
        if (ex_rs1_used && mem_reg_write_en && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs1)) begin
            forward_a_sel = 2'b10;
        end
        // Priority 2: WB Hazard (Older data)
        // Checked only if MEM doesn't match, ensuring consecutive writes to the 
        // same register result in the freshest data being forwarded.
        else if (ex_rs1_used && wb_reg_write_en && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs1)) begin
            forward_a_sel = 2'b01;
        end
        // Default: No data hazard, use standard decoded register value.
        else begin
            forward_a_sel = 2'b00;
        end
    end

    // ========================================================================
    // Forwarding Logic for Operand B (rs2)
    // ========================================================================
    always_comb begin
        // Priority 1: MEM Hazard (Most recent data)
        if (ex_rs2_used && mem_reg_write_en && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs2)) begin
            forward_b_sel = 2'b10;
        end
        // Priority 2: WB Hazard (Older data)
        else if (ex_rs2_used && wb_reg_write_en && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs2)) begin
            forward_b_sel = 2'b01;
        end
        // Default: No data hazard, use standard decoded register value.
        else begin
            forward_b_sel = 2'b00;
        end
    end

endmodule