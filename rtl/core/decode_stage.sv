`timescale 1ns / 1ps

module decode_stage (
    input  logic        clk,
    input  logic [31:0] if_id_inst,
    input  logic [31:0] if_id_pc,
    
    // Feedback from Writeback
    input  logic        wb_reg_write_en,
    input  logic [4:0]  wb_write_reg_addr,
    input  logic [31:0] wb_write_data,
    
    // Outputs
    output logic [31:0] id_read_data1,
    output logic [31:0] id_read_data2,
    output logic [31:0] id_imm,
    output logic [4:0]  id_rs1,
    output logic [4:0]  id_rs2,
    output logic [4:0]  id_rd,
    output logic [2:0]  id_funct3, 
    
    // Control Signals
    output logic        id_reg_write_en,
    output logic        id_mem_read_en,
    output logic        id_mem_write_en,
    output logic        id_mem_to_reg_sel,
    output logic [1:0]  id_alu_op_sel,
    output logic        id_alu_src_sel,
    output logic        id_jal_en,
    output logic        id_jalr_en,
    output logic        id_branch_en,
    
    // Forwarding logic signals
    output logic        id_rs1_used,
    output logic        id_rs2_used
);

    assign id_rs1    = if_id_inst[19:15];
    assign id_rs2    = if_id_inst[24:20];
    assign id_rd     = if_id_inst[11:7];
    assign id_funct3 = if_id_inst[14:12]; 

    // הגדרת משתנה עזר לאופקוד למניעת שגיאות ב-case
    logic [6:0] opcode;
    assign opcode = if_id_inst[6:0];

    // Register File Instance
    reg_file reg_file_inst (
        .clk(clk), .we(wb_reg_write_en),
        .read_reg1(id_rs1), .read_reg2(id_rs2),
        .write_reg(wb_write_reg_addr), .write_data(wb_write_data),
        .read_data1(id_read_data1), .read_data2(id_read_data2)
    );

    // Immediate Generator Instance
    imm_gen imm_gen_inst (
        .instr (if_id_inst),
        .imm   (id_imm)
    );

    always_comb begin
        // ערכי ברירת מחדל כדי למנוע Latches וערכי X
        id_reg_write_en   = 1'b0;
        id_mem_read_en    = 1'b0;
        id_mem_write_en   = 1'b0;
        id_mem_to_reg_sel = 1'b0;
        id_alu_op_sel     = 2'b00;
        id_alu_src_sel    = 1'b0;
        id_branch_en      = 1'b0;
        id_jal_en         = 1'b0;
        id_jalr_en        = 1'b0;
        id_rs1_used       = 1'b0;
        id_rs2_used       = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type (ADD, SUB...)
                id_reg_write_en = 1'b1;
                id_alu_op_sel   = 2'b10;
                id_rs1_used     = 1'b1;
                id_rs2_used     = 1'b1;
            end
            7'b0010011: begin // I-type ALU (ADDI)
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_alu_op_sel   = 2'b11; 
                id_rs1_used     = 1'b1;
            end
            7'b0000011: begin // Load (LW)
                id_reg_write_en   = 1'b1;
                id_mem_read_en    = 1'b1;
                id_mem_to_reg_sel = 1'b1;
                id_alu_src_sel    = 1'b1;
                id_rs1_used       = 1'b1;
            end
            7'b0100011: begin // Store (SW)
                id_mem_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_rs1_used     = 1'b1;
                id_rs2_used     = 1'b1; 
            end
            7'b1100011: begin // Branch (BEQ)
                id_branch_en   = 1'b1;
                id_alu_op_sel  = 2'b01;
                id_rs1_used    = 1'b1;
                id_rs2_used    = 1'b1;
            end
            7'b1101111: begin // JAL
                id_reg_write_en = 1'b1;
                id_jal_en       = 1'b1;
            end
            7'b1100111: begin // JALR
                id_reg_write_en = 1'b1;
                id_jalr_en      = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_rs1_used     = 1'b1;
            end
            7'b0110111: begin // LUI
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_alu_op_sel   = 2'b11;
            end
            default: ;
        endcase
    end
endmodule