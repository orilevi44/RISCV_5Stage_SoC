`timescale 1ns / 1ps

module alu_control (
    input  logic [2:0] alu_op,
    input  logic [2:0] funct3,
    input  logic       funct7_bit,
    output logic [3:0] alu_ctrl
);
    always_comb begin
        case (alu_op)
            // Load, Store, JALR: Always perform ADD to calculate address
            3'b000: alu_ctrl = 4'b0010; 

            // Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            3'b001: begin
                case (funct3)
                    3'b000, 3'b001: alu_ctrl = 4'b0110; // BEQ, BNE: Use SUB
                    3'b100, 3'b101: alu_ctrl = 4'b1000; // BLT, BGE: Use Signed SLT
                    3'b110, 3'b111: alu_ctrl = 4'b1010; // BLTU, BGEU: Use Unsigned SLTU
                    default:        alu_ctrl = 4'b0110;
                endcase
            end

            // R-type Instructions
            3'b010: begin
                case (funct3)
                    3'b000: alu_ctrl = (funct7_bit) ? 4'b0110 : 4'b0010; // SUB or ADD
                    3'b111: alu_ctrl = 4'b0000; // AND
                    3'b110: alu_ctrl = 4'b0001; // OR
                    3'b100: alu_ctrl = 4'b0011; // XOR
                    3'b001: alu_ctrl = 4'b0100; // SLL
                    3'b101: alu_ctrl = (funct7_bit) ? 4'b0111 : 4'b0101; // SRA or SRL
                    3'b010: alu_ctrl = 4'b1000; // SLT
                    3'b011: alu_ctrl = 4'b1010; // SLTU
                    default: alu_ctrl = 4'b0010;
                endcase
            end

            // I-type Instructions (ADDI, SLTI, SLLI, etc.)
            3'b011: begin
                case (funct3)
                    3'b000: alu_ctrl = 4'b0010; // ADDI: ADD
                    3'b010: alu_ctrl = 4'b1000; // SLTI: SLT
                    3'b011: alu_ctrl = 4'b1010; // SLTIU: SLTU
                    3'b100: alu_ctrl = 4'b0011; // XORI: XOR
                    3'b110: alu_ctrl = 4'b0001; // ORI: OR
                    3'b111: alu_ctrl = 4'b0000; // ANDI: AND
                    // Immediate Shifts (SLLI, SRLI/SRAI)
                    3'b001: alu_ctrl = 4'b0100; // SLLI
                    3'b101: alu_ctrl = (funct7_bit) ? 4'b0111 : 4'b0101; // SRAI or SRLI
                    default: alu_ctrl = 4'b0010;
                endcase
            end

            // LUI: Pass Immediate directly
            3'b100: alu_ctrl = 4'b1001; 

            default: alu_ctrl = 4'b0010;
        endcase
    end
endmodule