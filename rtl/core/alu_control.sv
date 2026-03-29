`timescale 1ns / 1ps

/**
 * ALU Control Unit
 * Decodes the ALU Opcode into specific ALU control signals.
 */
module alu_control (
    input  logic [1:0] alu_op,      // From Main Control
    input  logic [2:0] funct3,      // From Instruction[14:12]
    input  logic       funct7_bit,  // From Instruction[30]
    output logic [3:0] alu_ctrl     // Command sent to ALU
);

    always_comb begin
        case (alu_op)
            2'b00: alu_ctrl = 4'b0010; // Load/Store/JALR: Force ADD
            2'b01: alu_ctrl = 4'b0110; // Branch: Force SUBTRACT
            
            2'b10: begin               // R-type (Register-Register)
                case (funct3)
                    3'b000: alu_ctrl = (funct7_bit) ? 4'b0110 : 4'b0010; // SUB : ADD
                    3'b111: alu_ctrl = 4'b0000; // AND
                    3'b110: alu_ctrl = 4'b0001; // OR
                    3'b100: alu_ctrl = 4'b0011; // XOR
                    3'b001: alu_ctrl = 4'b0100; // SLL
                    3'b101: alu_ctrl = (funct7_bit) ? 4'b0111 : 4'b0101; // SRA : SRL
                    3'b010: alu_ctrl = 4'b1000; // SLT
                    default: alu_ctrl = 4'b0010;
                endcase
            end
            
            2'b11: begin               // I-type (Immediate)
                case (funct3)
                    3'b000: alu_ctrl = 4'b0010; // ADDI
                    3'b111: alu_ctrl = 4'b0000; // ANDI
                    3'b110: alu_ctrl = 4'b0001; // ORI
                    3'b100: alu_ctrl = 4'b0011; // XORI
                    default: alu_ctrl = 4'b0010;
                endcase
            end
            
            default: alu_ctrl = 4'b0010;
        endcase
    end
endmodule