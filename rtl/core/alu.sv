`timescale 1ns / 1ps

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_ctrl,
    output logic [31:0] result,
    output logic        zero
);

    logic [4:0] shamt;
    assign shamt = b[4:0];

    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a & b;                       // AND
            4'b0001: result = a | b;                       // OR
            4'b0010: result = a + b;                       // ADD
            4'b0011: result = a ^ b;                       // XOR
            4'b0100: result = a << shamt;                  // SLL (Logical Left Shift)
            4'b0101: result = a >> shamt;                  // SRL (Logical Right Shift)
            4'b0110: result = a - b;                       // SUB
            4'b0111: result = $signed(a) >>> shamt;        // SRA (Arithmetic Right Shift)
            
            // Signed Comparison (Used for SLT, BLT, BGE)
            4'b1000: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; 
            
            // Unsigned Comparison (Used for SLTU, BLTU, BGEU)
            4'b1010: result = (a < b) ? 32'd1 : 32'd0;     
            
            4'b1001: result = b;     // PASS_B (For LUI)
            
            default: result = 32'b0;
        endcase
    end

    // Zero flag: high if the result is exactly zero
    assign zero = (result == 32'b0);

endmodule