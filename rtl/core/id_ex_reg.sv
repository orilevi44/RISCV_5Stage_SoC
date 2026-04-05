`timescale 1ns / 1ps

module id_ex_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,
    
    // Inputs from ID Stage
    input  logic [31:0] id_pc,
    input  logic [31:0] id_read_data1,
    input  logic [31:0] id_read_data2,
    input  logic [31:0] id_imm,
    input  logic [31:0] id_inst,
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,
    input  logic [4:0]  id_rd,
    input  logic [2:0]  id_alu_op_sel,
    input  logic        id_alu_src_sel,
    input  logic        id_reg_write_en,
    input  logic        id_mem_read_en,
    input  logic        id_mem_write_en,
    input  logic        id_mem_to_reg_sel,
    input  logic        id_branch_en,
    input  logic        id_jal_en,
    input  logic        id_jalr_en,
    input  logic        id_auipc_en,       // Added for AUIPC
    input  logic        id_rs1_used,
    input  logic        id_rs2_used,
    
    // Outputs to EX Stage
    output logic [31:0] ex_pc,
    output logic [31:0] ex_read_data1,
    output logic [31:0] ex_read_data2,
    output logic [31:0] ex_imm,
    output logic [31:0] ex_inst,
    output logic [4:0]  ex_rs1,
    output logic [4:0]  ex_rs2,
    output logic [4:0]  ex_rd,
    output logic [2:0]  ex_alu_op_sel,
    output logic        ex_alu_src_sel,
    output logic        ex_reg_write_en,
    output logic        ex_mem_read_en,
    output logic        ex_mem_write_en,
    output logic        ex_mem_to_reg_sel,
    output logic        ex_branch_en,
    output logic        ex_jal_en,
    output logic        ex_jalr_en,
    output logic        ex_auipc_en,       // Added for AUIPC
    output logic        ex_rs1_used,
    output logic        ex_rs2_used,

    // CSR Signals
    input  logic [11:0] id_csr_addr,
    input  logic        id_csr_en,
    input  logic        id_valid_inst,
    
    output logic [11:0] ex_csr_addr,
    output logic        ex_csr_en,
    output logic        ex_valid_inst
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            ex_pc             <= 32'b0;
            ex_read_data1     <= 32'b0;
            ex_read_data2     <= 32'b0;
            ex_imm            <= 32'b0;
            ex_inst           <= 32'h00000013;
            ex_rs1            <= 5'b0;
            ex_rs2            <= 5'b0;
            ex_rd             <= 5'b0;
            ex_alu_op_sel     <= 3'b0;
            ex_alu_src_sel    <= 1'b0;
            ex_reg_write_en   <= 1'b0;
            ex_mem_read_en    <= 1'b0;
            ex_mem_write_en   <= 1'b0;
            ex_mem_to_reg_sel <= 1'b0;
            ex_branch_en      <= 1'b0;
            ex_jal_en         <= 1'b0;
            ex_jalr_en        <= 1'b0;
            ex_auipc_en       <= 1'b0;
            ex_csr_addr       <= 12'b0;
            ex_csr_en         <= 1'b0;
            ex_valid_inst     <= 1'b0;
            ex_rs1_used       <= 1'b0;
            ex_rs2_used       <= 1'b0;
        end else begin
            ex_pc             <= id_pc;
            ex_read_data1     <= id_read_data1;
            ex_read_data2     <= id_read_data2;
            ex_imm            <= id_imm;
            ex_inst           <= id_inst;
            ex_rs1            <= id_rs1;
            ex_rs2            <= id_rs2;
            ex_rd             <= id_rd;
            ex_alu_op_sel     <= id_alu_op_sel;
            ex_alu_src_sel    <= id_alu_src_sel;
            ex_reg_write_en   <= id_reg_write_en;
            ex_mem_read_en    <= id_mem_read_en;
            ex_mem_write_en   <= id_mem_write_en;
            ex_mem_to_reg_sel <= id_mem_to_reg_sel;
            ex_branch_en      <= id_branch_en;
            ex_jal_en         <= id_jal_en;
            ex_jalr_en        <= id_jalr_en;
            ex_auipc_en       <= id_auipc_en;
            ex_csr_addr       <= id_csr_addr;
            ex_csr_en         <= id_csr_en;
            ex_valid_inst     <= id_valid_inst;
            ex_rs1_used       <= id_rs1_used;
            ex_rs2_used       <= id_rs2_used;
        end
    end
endmodule