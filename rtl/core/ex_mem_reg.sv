`timescale 1ns / 1ps

module ex_mem_reg (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         flush,
    
    // Inputs from EX Stage
    input  logic [31:0]  ex_alu_result,
    input  logic [31:0]  ex_write_data,
    input  logic [31:0]  ex_branch_target,
    input  logic [4:0]   ex_rd_addr,
    input  logic [2:0]   ex_funct3,      
    input  logic         ex_alu_zero,    
    input  logic         ex_valid_inst,      // <--- ADDED for CSR
    
    // Control Signal Inputs from EX
    input  logic         ex_reg_write_en,
    input  logic         ex_mem_to_reg_sel,
    input  logic         ex_mem_read_en,
    input  logic         ex_mem_write_en,
    input  logic         ex_branch_en, 
    input  logic         ex_jal_en,
    input  logic         ex_jalr_en,

    // Outputs to MEM Stage
    output logic [31:0]  mem_alu_result,
    output logic [31:0]  mem_write_data,
    output logic [31:0]  mem_branch_target,
    output logic [4:0]   mem_rd_addr,
    output logic [2:0]   mem_funct3,     
    output logic         mem_alu_zero,   
    output logic         mem_valid_inst,     // <--- ADDED for CSR
    
    // Control Signal Outputs to MEM
    output logic         mem_reg_write_en,
    output logic         mem_mem_to_reg_sel,
    output logic         mem_mem_read_en,
    output logic         mem_mem_write_en,
    output logic         mem_branch_en,
    output logic         mem_jal_en,
    output logic         mem_jalr_en
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_alu_result      <= 32'b0;
            mem_write_data      <= 32'b0;
            mem_branch_target   <= 32'b0;
            mem_rd_addr         <= 5'b0;
            mem_funct3          <= 3'b0;
            mem_alu_zero        <= 1'b0;    
            mem_valid_inst      <= 1'b0;
            mem_reg_write_en    <= 1'b0;
            mem_mem_to_reg_sel  <= 1'b0;
            mem_mem_read_en     <= 1'b0;
            mem_mem_write_en    <= 1'b0;
            mem_branch_en       <= 1'b0;
            mem_jal_en          <= 1'b0;
            mem_jalr_en         <= 1'b0;
        end 
        else if (flush) begin
            // Clear control and validity on flush
            mem_valid_inst      <= 1'b0;
            mem_reg_write_en    <= 1'b0;
            mem_mem_read_en     <= 1'b0;
            mem_mem_write_en    <= 1'b0;
            mem_branch_en       <= 1'b0;
            mem_jal_en          <= 1'b0;
            mem_jalr_en         <= 1'b0;
            // Target and result can stay for logic stability
        end 
        else begin
            mem_alu_result      <= ex_alu_result;
            mem_write_data      <= ex_write_data;
            mem_branch_target   <= ex_branch_target;
            mem_rd_addr         <= ex_rd_addr;
            mem_funct3          <= ex_funct3;
            mem_alu_zero        <= ex_alu_zero; 
            mem_valid_inst      <= ex_valid_inst;
            mem_reg_write_en    <= ex_reg_write_en;
            mem_mem_to_reg_sel  <= ex_mem_to_reg_sel;
            mem_mem_read_en     <= ex_mem_read_en;
            mem_mem_write_en    <= ex_mem_write_en;
            mem_branch_en       <= ex_branch_en;
            mem_jal_en          <= ex_jal_en;
            mem_jalr_en         <= ex_jalr_en;
        end
    end
endmodule