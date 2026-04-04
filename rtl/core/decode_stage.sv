`timescale 1ns / 1ps

/**
 * Decode Stage
 * -------------------
 * Responsible for:
 * 1. Extracting register addresses (rs1, rs2, rd) and funct3.
 * 2. Instantiating the Register File and Immediate Generator.
 * 3. Generating control signals based on the Opcode.
 * 4. Identifying register usage for Hazard Detection and Forwarding.
 */
module decode_stage (
    input  logic        clk,
    input  logic [31:0] if_id_inst,
    input  logic [31:0] if_id_pc,
    
    // Feedback from Writeback Stage
    input  logic        wb_reg_write_en,
    input  logic [4:0]  wb_write_reg_addr,
    input  logic [31:0] wb_write_data,
    
    // Data Outputs
    output logic [31:0] id_read_data1,
    output logic [31:0] id_read_data2,
    output logic [31:0] id_imm,
    output logic [4:0]  id_rs1,
    output logic [4:0]  id_rs2,
    output logic [4:0]  id_rd,
    output logic [2:0]  id_funct3, 
    
    // Main Control Signals
    output logic        id_reg_write_en,
    output logic        id_mem_read_en,
    output logic        id_mem_write_en,
    output logic        id_mem_to_reg_sel,
    output logic [2:0]  id_alu_op_sel,    // 3-bit selection for ALU Control
    output logic        id_alu_src_sel,   // 0 = Register, 1 = Immediate
    output logic        id_jal_en,
    output logic        id_jalr_en,
    output logic        id_branch_en,
    output logic        id_auipc_en,      // New signal for AUIPC logic
    
    // Status signals for Hazard/Forwarding units
    output logic        id_rs1_used,
    output logic        id_rs2_used
);

    // --- Field Extraction ---
    assign id_rs1    = if_id_inst[19:15];
    assign id_rs2    = if_id_inst[24:20];
    assign id_rd     = if_id_inst[11:7];
    assign id_funct3 = if_id_inst[14:12]; 

    logic [6:0] opcode;
    assign opcode = if_id_inst[6:0];

    // --- Register File Instance ---
    reg_file reg_file_inst (
        .clk(clk), 
        .we(wb_reg_write_en),
        .read_reg1(id_rs1), 
        .read_reg2(id_rs2),
        .write_reg(wb_write_reg_addr), 
        .write_data(wb_write_data),
        .read_data1(id_read_data1), 
        .read_data2(id_read_data2)
    );

    // --- Immediate Generator Instance ---
    imm_gen imm_gen_inst (
        .instr (if_id_inst),
        .imm   (id_imm)
    );

    // --- Control Signal Generation Logic ---
    always_comb begin
        // Default values to prevent latches
        id_reg_write_en   = 1'b0;
        id_mem_read_en    = 1'b0;
        id_mem_write_en   = 1'b0;
        id_mem_to_reg_sel = 1'b0;
        id_alu_op_sel     = 3'b000;
        id_alu_src_sel    = 1'b0;
        id_branch_en      = 1'b0;
        id_jal_en         = 1'b0;
        id_jalr_en        = 1'b0;
        id_auipc_en       = 1'b0;
        id_rs1_used       = 1'b0;
        id_rs2_used       = 1'b0;

        case (opcode)
            // R-type (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU)
            7'b0110011: begin 
                id_reg_write_en = 1'b1;
                id_alu_op_sel   = 3'b010; 
                id_rs1_used     = 1'b1;
                id_rs2_used     = 1'b1;
            end

            // I-type ALU (ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI)
            7'b0010011: begin 
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_alu_op_sel   = 3'b011; 
                id_rs1_used     = 1'b1;
            end

            // Load Instructions (LB, LH, LW, LBU, LHU)
            7'b0000011: begin 
                id_reg_write_en   = 1'b1;
                id_mem_read_en    = 1'b1;
                id_mem_to_reg_sel = 1'b1;
                id_alu_src_sel    = 1'b1;
                id_alu_op_sel     = 3'b000; // Performs ADD for address calc
                id_rs1_used       = 1'b1;
            end

            // Store Instructions (SB, SH, SW)
            7'b0100011: begin 
                id_mem_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_alu_op_sel   = 3'b000; // Performs ADD for address calc
                id_rs1_used     = 1'b1;
                id_rs2_used     = 1'b1; 
            end

            // Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            7'b1100011: begin 
                id_branch_en   = 1'b1;
                id_alu_op_sel  = 3'b001; 
                id_rs1_used    = 1'b1;
                id_rs2_used    = 1'b1;
            end

            // JAL (Jump and Link)
            7'b1101111: begin 
                id_reg_write_en = 1'b1;
                id_jal_en       = 1'b1;
            end

            // JALR (Jump and Link Register)
            7'b1100111: begin 
                id_reg_write_en = 1'b1;
                id_jalr_en      = 1'b1;
                id_alu_src_sel  = 1'b1;
                id_alu_op_sel   = 3'b000; // Performs ADD for target calc
                id_rs1_used     = 1'b1;
            end
            
            // LUI (Load Upper Immediate)
            7'b0110111: begin 
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;   
                id_alu_op_sel   = 3'b100; // Pass-B logic in ALU_Control
                id_rs1_used     = 1'b0;   
                id_rs2_used     = 1'b0;
            end

            // AUIPC (Add Upper Immediate to PC)
            7'b0010111: begin
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;   
                id_alu_op_sel   = 3'b000; // Use ADD in ALU_Control
                id_auipc_en     = 1'b1;   // Signals Execute stage to use PC as Operand A
                id_rs1_used     = 1'b0;   
                id_rs2_used     = 1'b0;
            end
            
            default: ;
        endcase
    end
endmodule