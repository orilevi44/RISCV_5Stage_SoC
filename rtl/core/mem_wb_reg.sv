`timescale 1ns / 1ps

/**
 * MEM/WB Pipeline Register
 * Holds the results of the Memory stage for the final Writeback stage.
 * This is the last synchronization point in the pipeline.
 */
module mem_wb_reg (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Data Inputs from Memory (MEM) ---
    input  logic [31:0] mem_alu_res,      // ALU result passed from MEM
    input  logic [31:0] mem_mem_data,     // Data read from RAM
    input  logic [4:0]  mem_rd_addr,      // Destination register address
    
    // --- Control Signal Inputs from Memory ---
    input  logic        mem_reg_write_en, // Enable signal to update Register File
    input  logic        mem_mem_to_reg_sel, // Mux selector: 1=Memory, 0=ALU

    // --- Data Outputs to Writeback (WB) ---
    output logic [31:0] wb_alu_res,
    output logic [31:0] wb_mem_data,
    output logic [4:0]  wb_rd_addr,
    
    // --- Control Signal Outputs to Writeback ---
    output logic        wb_reg_write_en,
    output logic        wb_mem_to_reg_sel
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: Clear all buffered data and control signals
            wb_alu_res        <= 32'b0;
            wb_mem_data       <= 32'b0;
            wb_rd_addr        <= 5'b0;
            wb_reg_write_en   <= 1'b0;
            wb_mem_to_reg_sel <= 1'b0;
        end else begin
            // Pass values from MEM to WB stage
            wb_alu_res        <= mem_alu_res;
            wb_mem_data       <= mem_mem_data;
            wb_rd_addr        <= mem_rd_addr;
            wb_reg_write_en   <= mem_reg_write_en;
            wb_mem_to_reg_sel <= mem_mem_to_reg_sel;
        end
    end

endmodule