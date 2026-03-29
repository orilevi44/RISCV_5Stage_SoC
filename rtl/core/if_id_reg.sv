`timescale 1ns / 1ps

/**
 * IF/ID Pipeline Register
 * Separates Fetch (IF) and Decode (ID) stages.
 */
module if_id_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,          // Clear register on Control Hazard (insert NOP)
    input  logic        en,             // Enable signal (0 = stall for Data Hazard)

    input  logic [31:0] if_pc,          // PC from Fetch
    input  logic [31:0] if_inst,        // Instruction from Fetch

    output logic [31:0] id_pc,          // PC to Decode
    output logic [31:0] id_inst         // Instruction to Decode
);

    // Standard RISC-V NOP: addi x0, x0, 0
    localparam [31:0] NOP_INST = 32'h00000013;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc   <= 32'b0;
            id_inst <= NOP_INST;
        end else if (flush) begin
            id_pc   <= 32'b0;
            id_inst <= NOP_INST; // Inject NOP on jump/branch
        end else if (en) begin
            id_pc   <= if_pc;
            id_inst <= if_inst;
        end
    end
endmodule