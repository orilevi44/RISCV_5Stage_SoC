`timescale 1ns / 1ps

module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm
);
    // חילוץ האופקוד למשתנה עזר
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    // הכנה מראש של כל הפורמטים (חוסך שגיאות בתוך ה-always_comb)
    logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;

    assign i_imm = {{20{instr[31]}}, instr[31:20]};
    assign s_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign b_imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    assign u_imm = {instr[31:12], 12'b0};
    assign j_imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    always_comb begin
        case (opcode)
            7'b0000011, 7'b0010011, 7'b1100111: imm = i_imm; // I-Type
            7'b0100011:                         imm = s_imm; // S-Type
            7'b1100011:                         imm = b_imm; // B-Type
            7'b0110111, 7'b0010111:             imm = u_imm; // U-Type
            7'b1101111:                         imm = j_imm; // J-Type
            default:                            imm = 32'b0;
        endcase
    end
endmodule