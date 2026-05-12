`timescale 1ns / 1ps

/**
 * Forwarding Unit
 * ---------------
 * This unit resolves Data Hazards by providing the most recent data 
 * from MEM or WB stages directly to the ALU inputs in the EX stage.
 *
 * Priority: MEM stage has higher priority as it contains the absolute 
 * most recent version of a register's data.
 */
module forwarding_unit (
    input  logic clk,
    
    // Inputs from Execute Stage
    input  logic [4:0]  ex_rs1,           // Source Register 1
    input  logic [4:0]  ex_rs2,           // Source Register 2
    input  logic        ex_rs1_used,      // High if current instruction reads rs1
    input  logic        ex_rs2_used,      // High if current instruction reads rs2
    
    // Inputs from Memory Stage (MEM Hazard)
    input  logic [4:0]  mem_rd_addr,      // Destination register in MEM stage
    input  logic        mem_reg_write_en, // High if MEM stage writes to Register File
    
    // Inputs from Writeback Stage (WB Hazard)
    input  logic [4:0]  wb_rd_addr,       // Destination register in WB stage
    input  logic        wb_reg_write_en,  // High if WB stage writes to Register File
    
    // Selection outputs for ALU Muxes
    // 00: RegFile | 01: WB Stage | 10: MEM Stage
    output logic [1:0]  forward_a_sel,
    output logic [1:0]  forward_b_sel
);

    // --- Forwarding for Operand A (rs1) ---
    always_comb begin
        // Priority 1: Forward from MEM stage (most recent)
        if (ex_rs1_used && mem_reg_write_en && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs1)) begin
            forward_a_sel = 2'b10;
        end
        // Priority 2: Forward from WB stage
        else if (ex_rs1_used && wb_reg_write_en && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs1)) begin
            forward_a_sel = 2'b01;
        end
        // Default: Use data from Register File
        else begin
            forward_a_sel = 2'b00;
        end
    end

    // --- Forwarding for Operand B (rs2) ---
    always_comb begin
        // Priority 1: Forward from MEM stage (most recent)
        if (ex_rs2_used && mem_reg_write_en && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs2)) begin
            forward_b_sel = 2'b10;
        end
        // Priority 2: Forward from WB stage
        else if (ex_rs2_used && wb_reg_write_en && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs2)) begin
            forward_b_sel = 2'b01;
        end
        // Default: Use data from Register File
        else begin
            forward_b_sel = 2'b00;
        end
    end

    // --- Debug Monitors for Simulation ---
    // always @(posedge clk) begin
    //     if (forward_a_sel == 2'b10) 
    //         $display("[FWD] MEM Hazard detected on rs1 (x%0d). Bypassing data!", ex_rs1);
    //     if (forward_b_sel == 2'b10) 
    //         $display("[FWD] MEM Hazard detected on rs2 (x%0d). Bypassing data!", ex_rs2);
    //     if (forward_a_sel == 2'b01) 
    //         $display("[FWD] WB Hazard detected on rs1 (x%0d). Bypassing data!", ex_rs1);
    //     if (forward_b_sel == 2'b01) 
    //         $display("[FWD] WB Hazard detected on rs2 (x%0d). Bypassing data!", ex_rs2);
    // end

endmodule