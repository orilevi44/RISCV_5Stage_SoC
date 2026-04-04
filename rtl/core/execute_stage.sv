`timescale 1ns / 1ps

/**
 * Execute Stage
 * -------------------
 * This version includes the missing 'ex_branch_en' port and fixes
 * Icarus Verilog 'constant select' warnings.
 */
module execute_stage (
    input  logic [31:0] ex_pc,
    input  logic [31:0] ex_read_data1,
    input  logic [31:0] ex_read_data2,
    input  logic [31:0] ex_imm,
    input  logic [31:0] ex_inst,
    
    // Forwarding inputs
    input  logic [31:0] mem_forward_data, 
    input  logic [31:0] wb_forward_data,  
    input  logic [1:0]  forward_a_sel,
    input  logic [1:0]  forward_b_sel,
    
    // Control inputs
    input  logic [2:0]  ex_alu_op_sel,
    input  logic        ex_alu_src_sel,
    input  logic        ex_jal_en,   
    input  logic        ex_jalr_en,   
    input  logic        ex_auipc_en,
    input  logic        ex_branch_en,     // ADDED: This fixes the port error

    // Outputs
    output logic [31:0] ex_branch_target,
    output logic [31:0] ex_alu_result,
    output logic [31:0] ex_write_data_mem,
    output logic        ex_alu_zero
);

    logic [31:0] alu_in1;
    logic [31:0] alu_rs2_fwd;
    logic [31:0] alu_in2;
    logic [3:0]  alu_ctrl_wire; 
    logic [31:0] alu_raw_out;   

    // Local wires to avoid Icarus 'constant select' errors
    logic [2:0] f3;
    logic       f7_bit;
    assign f3     = ex_inst[14:12];
    assign f7_bit = ex_inst[30];

    // 1. Operand A Selection (Logic for AUIPC vs RS1)
    always_comb begin
        if (ex_auipc_en) begin
            alu_in1 = ex_pc;
        end else begin
            case (forward_a_sel)
                2'b00:   alu_in1 = ex_read_data1;
                2'b01:   alu_in1 = wb_forward_data;
                2'b10:   alu_in1 = mem_forward_data;
                default: alu_in1 = ex_read_data1;
            endcase
        end
    end

    // 2. Operand B Selection (Forwarding rs2)
    always_comb begin
        case (forward_b_sel)
            2'b00:   alu_rs2_fwd = ex_read_data2;
            2'b01:   alu_rs2_fwd = wb_forward_data;
            2'b10:   alu_rs2_fwd = mem_forward_data;
            default: alu_rs2_fwd = ex_read_data2;
        endcase
    end
    
    // 3. ALU Input B Multiplexer
    assign alu_in2 = (ex_alu_src_sel) ? ex_imm : alu_rs2_fwd;

    // 4. Address Target Calculation
    assign ex_branch_target = (ex_jalr_en) ? (alu_in1 + ex_imm) : (ex_pc + ex_imm);

    // 5. Data to be stored in RAM
    assign ex_write_data_mem = alu_rs2_fwd;

    // 6. Writeback Selection (ALU vs Jump Link)
    assign ex_alu_result = (ex_jal_en || ex_jalr_en) ? (ex_pc + 32'd4) : alu_raw_out;

    // Sub-module Instances
    alu_control alu_control_unit (
        .alu_op     (ex_alu_op_sel),
        .funct3     (f3),
        .funct7_bit (f7_bit),
        .alu_ctrl   (alu_ctrl_wire)
    );

    alu alu_unit (
        .a        (alu_in1),
        .b        (alu_in2),
        .alu_ctrl (alu_ctrl_wire),
        .result   (alu_raw_out),
        .zero     (ex_alu_zero)
    );

endmodule