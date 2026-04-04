`timescale 1ns / 1ps

/**
 * Program Counter Register
 * ------------------------
 * Holds the address of the instruction to be fetched.
 * Supports active-low reset and stall (via 'en' signal).
 */
module pc_reg (
    input  logic        clk,
    input  logic        rst_n,    
    input  logic        en,         // 1 = Update PC, 0 = Stall
    input  logic [31:0] next_pc,    // Target address
    output logic [31:0] pc_out      // Current PC address
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'b0;        // Start execution at address 0x0
        end else if (en) begin
            pc_out <= next_pc;      
        end
    end

endmodule