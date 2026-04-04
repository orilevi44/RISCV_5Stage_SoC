module alu_control (
    input  logic [2:0] alu_op,
    input  logic [2:0] funct3,
    input  logic       funct7_bit,
    output logic [3:0] alu_ctrl  // חזרה ל-4 ביטים: [3:0]
);
    always_comb begin
        case (alu_op)
            3'b000: alu_ctrl = 4'b0010; // Load/Store/JALR: ADD
            3'b001: alu_ctrl = 4'b0110; // Branch: SUB
            3'b010: begin               // R-type
                case (funct3)
                    3'b000: alu_ctrl = (funct7_bit) ? 4'b0110 : 4'b0010;
                    3'b111: alu_ctrl = 4'b0000;
                    3'b110: alu_ctrl = 4'b0001;
                    3'b100: alu_ctrl = 4'b0011;
                    3'b001: alu_ctrl = 4'b0100;
                    3'b101: alu_ctrl = (funct7_bit) ? 4'b0111 : 4'b0101;
                    3'b010: alu_ctrl = 4'b1000;
                    default: alu_ctrl = 4'b0010;
                endcase
            end
            3'b011: begin               // I-type
                case (funct3)
                    3'b000: alu_ctrl = 4'b0010;
                    3'b111: alu_ctrl = 4'b0000;
                    3'b110: alu_ctrl = 4'b0001;
                    3'b100: alu_ctrl = 4'b0011;
                    default: alu_ctrl = 4'b0010;
                endcase
            end
            3'b100: alu_ctrl = 4'b1001; // LUI: Pass-B
            default: alu_ctrl = 4'b0010;
        endcase
    end
endmodule