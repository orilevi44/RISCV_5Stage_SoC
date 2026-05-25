`timescale 1ns / 1ps

/**
 * Execute Stage (EX) - Includes CSR and Forwarding support
 * -------------------------------------------------------------------------
 * This stage performs the core arithmetic and logic operations.
 * Key responsibilities:
 * 1. Resolving data hazards using the Forwarding Unit.
 * 2. Executing ALU operations.
 * 3. Calculating branch and jump target addresses.
 * 4. Multiplexing the final result (ALU out, CSR read data, or PC+4 for jumps).
 */
module execute_stage (
    // Inputs from Decode Stage (via IF/ID -> ID/EX pipeline registers)
    input  logic [31:0] ex_pc,           // Program Counter of the current instruction
    input  logic [31:0] ex_read_data1,   // Raw RS1 value from the Register File
    input  logic [31:0] ex_read_data2,   // Raw RS2 value from the Register File
    input  logic [31:0] ex_imm,          // Sign-extended immediate value
    input  logic [31:0] ex_inst,         // 32-bit instruction word
    
    // CSR Inputs
    input  logic [31:0] ex_csr_rdata,    // Data read from the CSR Unit
    input  logic        ex_csr_en,       // Control signal: Active for CSR instructions

    // Forwarding inputs (Hazard resolution)
    input  logic [31:0] mem_forward_data, // Forwarded data from the MEM stage (ALU result)
    input  logic [31:0] wb_forward_data,  // Forwarded data from the WB stage (Load or ALU result)
    input  logic [1:0]  forward_a_sel,    // Selector for ALU input A forwarding
    input  logic [1:0]  forward_b_sel,    // Selector for ALU input B forwarding
    
    // Control inputs (from Decode)
    input  logic [2:0]  ex_alu_op_sel,    // Base ALU operation code
    input  logic        ex_alu_src_sel,   // ALU input B selector (0 = RS2, 1 = Immediate)
    input  logic        ex_jal_en,        // Control signal: Jump and Link
    input  logic        ex_jalr_en,       // Control signal: Jump and Link Register
    input  logic        ex_auipc_en,      // Control signal: Add Upper Immediate to PC
    input  logic        ex_branch_en,     // Control signal: Branch instruction

    // Outputs (to EX/MEM pipeline register)
    output logic [31:0] ex_branch_target, // Calculated target address for branches/jumps
    output logic [31:0] ex_alu_result,    // Final data to be passed down the pipeline
    output logic [31:0] ex_rs1_fwd_out,   // Forwarded RS1 value (Crucial for CSR writes)
    output logic [31:0] ex_write_data_mem,// Data to be written to RAM (for Store instructions)
    output logic        ex_alu_zero       // Flag: High if ALU result is zero (used for branches)
);

    // Internal wires
    logic [31:0] alu_in1;       // Final multiplexed input A for the ALU
    logic [31:0] alu_rs2_fwd;   // Forwarded value of RS2
    logic [31:0] alu_in2;       // Final multiplexed input B for the ALU
    logic [3:0]  alu_ctrl_wire; // Specific ALU control signal (e.g., 4'b0010 for ADD)
    logic [31:0] alu_raw_out;   // Raw computational result from the ALU

    // Local wires for instruction field extraction (avoids synthesis warnings)
    logic [2:0] f3;
    logic       f7_bit;
    assign f3     = ex_inst[14:12]; // funct3 field
    assign f7_bit = ex_inst[30];    // specific bit from funct7 (distinguishes ADD/SUB, SRL/SRA)

    // ==============================================================================
    // 1. Operand A Selection & Forwarding
    // ==============================================================================
    // Selects the source for ALU Input A. 
    // Resolves data hazards via forwarding, and handles AUIPC which requires the PC.
    always_comb begin
        if (ex_auipc_en) begin
            alu_in1 = ex_pc; // AUIPC uses PC instead of RS1
        end else begin
            case (forward_a_sel)
                2'b00:   alu_in1 = ex_read_data1;    // No hazard, use original RS1
                2'b01:   alu_in1 = wb_forward_data;  // Forward from Writeback stage
                2'b10:   alu_in1 = mem_forward_data; // Forward from Memory stage
                default: alu_in1 = ex_read_data1;
            endcase
        end
    end
    
    // Export the resolved RS1 value. The CSR unit needs this to perform writes
    // correctly if the RS1 value was dependent on a previous instruction.
    assign ex_rs1_fwd_out = alu_in1;

    // ==============================================================================
    // 2. Operand B Forwarding
    // ==============================================================================
    // Resolves data hazards for RS2. This forwarded value might be used by the ALU,
    // or routed to the data memory for Store operations.
    always_comb begin
        case (forward_b_sel)
            2'b00:   alu_rs2_fwd = ex_read_data2;    // No hazard, use original RS2
            2'b01:   alu_rs2_fwd = wb_forward_data;  // Forward from Writeback stage
            2'b10:   alu_rs2_fwd = mem_forward_data; // Forward from Memory stage
            default: alu_rs2_fwd = ex_read_data2;
        endcase
    end
    
    // ==============================================================================
    // 3. ALU Input B Multiplexer
    // ==============================================================================
    // Selects between the forwarded RS2 value (R-Type) or the Immediate value (I-Type/S-Type)
    assign alu_in2 = (ex_alu_src_sel) ? ex_imm : alu_rs2_fwd;

    // ==============================================================================
    // 4. Address Target Calculation
    // ==============================================================================
    // Calculates the destination address for Branches and Jumps.
    // JALR uses RS1 (alu_in1) + Immediate. Others use PC + Immediate.
    assign ex_branch_target = (ex_jalr_en) ? (alu_in1 + ex_imm) : (ex_pc + ex_imm);

    // ==============================================================================
    // 5. Store Data Routing
    // ==============================================================================
    // Routes the hazard-resolved RS2 value to the Data Memory for Store instructions.
    assign ex_write_data_mem = alu_rs2_fwd;

    // ==============================================================================
    // 6. Final Result Selection (Execution Stage Output Mux)
    // ==============================================================================
    // Determines what data gets passed down the pipeline as the "result".
    always_comb begin
        if (ex_csr_en) begin
            ex_alu_result = ex_csr_rdata;  // Route CSR read data
        end else if (ex_jal_en || ex_jalr_en) begin
            ex_alu_result = ex_pc + 32'd4; // For Jumps, save the return address (PC+4) into the register
        end else begin
            ex_alu_result = alu_raw_out;   // Standard ALU computational result
        end
    end

    // ==============================================================================
    // Sub-module Instances
    // ==============================================================================

    // ALU Control Unit: Decodes standard control signals and instruction fields into a specific ALU operation
    alu_control alu_control_unit (
        .alu_op     (ex_alu_op_sel),
        .funct3     (f3),
        .funct7_bit (f7_bit),
        .alu_ctrl   (alu_ctrl_wire)
    );

    // The Arithmetic Logic Unit (ALU): Performs the actual mathematical/logical computation
    alu alu_unit (
        .a        (alu_in1),
        .b        (alu_in2),
        .alu_ctrl (alu_ctrl_wire),
        .result   (alu_raw_out),
        .zero     (ex_alu_zero)
    );

endmodule