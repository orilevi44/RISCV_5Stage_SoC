`timescale 1ns / 1ps

/**
 * Program Counter Register
 * Holds the current instruction address.
 */
module pc_reg (
    input  logic        clk,
    input  logic        rst_n,      // Active-low asynchronous reset
    input  logic        en,         // Enable: logic 1 allows PC to update
    input  logic [31:0] next_pc,    // Address of the next instruction to fetch
    output logic [31:0] pc_out      // Current PC address
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'b0;        // Reset PC to the start of memory (0x0)
        end else if (en) begin
            pc_out <= next_pc;      // Update PC with the next address
        end
    end

endmodule