`timescale 1ns / 1ps

/**
 * Decode Stage (ID)
 * -------------------------------------------------------------------------
 * Parses the incoming 32-bit instruction,
 * fetches operands from the Register File, generates the required immediate value,
 * and decodes the opcode into specific control signals for downstream stages (EX, MEM, WB).
 */
module decode_stage (
    input  logic        clk,
    input  logic [31:0] if_id_inst,      // Instruction from IF/ID register
    input  logic [31:0] if_id_pc,        // PC of the current instruction
    
    // Feedback from Writeback Stage (WB)
    input  logic        wb_reg_write_en,   // Is WB writing to a register?
    input  logic [4:0]  wb_write_reg_addr, // Destination register from WB
    input  logic [31:0] wb_write_data,     // Data payload from WB
    
    // Data Outputs to EX stage
    output logic [31:0] id_read_data1,   // Value of rs1
    output logic [31:0] id_read_data2,   // Value of rs2
    output logic [31:0] id_imm,          // Extended immediate value
    output logic [4:0]  id_rs1,          // Source register 1 address
    output logic [4:0]  id_rs2,          // Source register 2 address
    output logic [4:0]  id_rd,           // Destination register address
    output logic [2:0]  id_funct3,       // Sub-operation field
    
    // Main Control Signals
    output logic        id_reg_write_en,   // Will this instruction write to a register?
    output logic        id_mem_read_en,    // Does it read from Data Memory?
    output logic        id_mem_write_en,   // Does it write to Data Memory?
    output logic        id_mem_to_reg_sel, // MUX select: 1=Memory Data, 0=ALU Result
    output logic [2:0]  id_alu_op_sel,     // Operation category for the ALU
    output logic        id_alu_src_sel,    // MUX select: 1=Immediate, 0=rs2
    output logic        id_jal_en,         // Is it an unconditional JAL?
    output logic        id_jalr_en,        // Is it an unconditional JALR?
    output logic        id_branch_en,      // Is it a conditional branch?
    output logic        id_auipc_en,       // Is it AUIPC?
    
    // Status signals for Hazard Detection and Forwarding units
    output logic        id_rs1_used,       // Does this instruction actually read rs1?
    output logic        id_rs2_used,       // Does this instruction actually read rs2?
    
    // System & Status Signals
    output logic        id_csr_en,         // Control and Status Register operation
    output logic        id_valid_inst      // Flag indicating a valid, non-NOP instruction
);

    logic [6:0] opcode;
    assign opcode = if_id_inst[6:0];

    // ==============================================================================
    // 1. Instruction Field Extraction
    // ==============================================================================
    // Special handling for LUI (U-Type): It doesn't use rs1. Force it to 0 to prevent 
    // false positive hazard detections based on garbage bits in the rs1 position.
    assign id_rs1    = (opcode == 7'b0110111) ? 5'b0 : if_id_inst[19:15];
    assign id_rs2    = if_id_inst[24:20];
    assign id_rd     = if_id_inst[11:7];
    assign id_funct3 = if_id_inst[14:12]; 

    // An instruction is considered valid if it's not a standard NOP and has a non-zero opcode
    assign id_valid_inst = (if_id_inst != 32'h00000013) && (opcode != 7'b0);

    // ==============================================================================
    // 2. Register File Instance
    // ==============================================================================
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

    // ==============================================================================
    // 3. Immediate Generator Instance
    // ==============================================================================
    imm_gen imm_gen_inst (
        .instr (if_id_inst),
        .imm   (id_imm)
    );

    // ==============================================================================
    // 4. Main Control Decoder
    // ==============================================================================
    always_comb begin
        // --- Setup Defaults ---
        // Good practice: Initialize all signals to safe 0/inactive states to prevent 
        // inferred latches and keep the case statement clean.
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
        id_csr_en         = 1'b0;
        id_rs1_used       = 1'b0;
        id_rs2_used       = 1'b0;

        // --- Decode Opcode ---
        case (opcode)
            7'b0110011: begin // R-type (add, sub, and, or...)
                id_reg_write_en = 1'b1;
                id_alu_op_sel   = 3'b010; 
                id_rs1_used     = 1'b1;
                id_rs2_used     = 1'b1;
            end
            7'b0010011: begin // I-type ALU (addi, andi, ori...)
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;     // Use immediate for Operand B
                id_alu_op_sel   = 3'b011; 
                id_rs1_used     = 1'b1;
            end
            7'b0000011: begin // Loads (lw, lh, lb...)
                id_reg_write_en   = 1'b1;
                id_mem_read_en    = 1'b1;
                id_mem_to_reg_sel = 1'b1;   // Data comes from memory
                id_alu_src_sel    = 1'b1;   // Address calculation: rs1 + imm
                id_alu_op_sel     = 3'b000; // ALU performs ADD for address
                id_rs1_used       = 1'b1;
            end
            7'b0100011: begin // Stores S-type (sw, sh, sb)
                id_mem_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;     // Address calculation: rs1 + imm
                id_alu_op_sel   = 3'b000; 
                id_rs1_used     = 1'b1;     // Base address
                id_rs2_used     = 1'b1;     // Data to store
            end
            7'b1100011: begin // Branches B-type (beq, bne...)
                id_branch_en   = 1'b1;
                id_alu_op_sel  = 3'b001;    // ALU performs SUB to compare
                id_rs1_used    = 1'b1;
                id_rs2_used    = 1'b1;
            end
            7'b1101111: begin // JAL (Jump and Link)
                id_reg_write_en = 1'b1;     // Save return address
                id_jal_en       = 1'b1;
            end
            7'b1100111: begin // JALR (Jump and Link Register)
                id_reg_write_en = 1'b1;
                id_jalr_en      = 1'b1;
                id_alu_src_sel  = 1'b1;     // Address: rs1 + imm
                id_alu_op_sel   = 3'b000; 
                id_rs1_used     = 1'b1;
            end
            7'b0110111: begin // LUI (Load Upper Immediate)
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;   
                id_alu_op_sel   = 3'b000; 
                // rs1 and rs2 are NOT used
            end
            7'b0010111: begin // AUIPC (Add Upper Immediate to PC)
                id_reg_write_en = 1'b1;
                id_alu_src_sel  = 1'b1;   
                id_alu_op_sel   = 3'b000; 
                id_auipc_en     = 1'b1;   
            end
            7'b1110011: begin // SYSTEM instructions (CSR Operations / MRET)
                if (id_funct3 == 3'b000) begin
                    // MRET (Machine Return)
                    // Handled down the pipeline, no general registers written.
                end else begin
                    // CSR Access (csrr, csrw, etc.)
                    id_reg_write_en   = 1'b1;   
                    id_alu_op_sel     = 3'b000; 
                    id_csr_en         = 1'b1;   
                    id_rs1_used       = 1'b1;
                end
            end
            default: ; // All signals remain at safe default (0)
        endcase
    end
endmodule