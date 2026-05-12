`timescale 1ns / 1ps

// IF/ID Pipeline Register
// Latches PC and instruction from the Fetch stage into the Decode stage.
// Supports stall (en=0 freezes) and flush (inserts NOP on branch/jump).
module if_id_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,
    input  logic        en,

    input  logic [31:0] if_pc,          
    input  logic [31:0] if_inst,        

    output logic [31:0] id_pc,          
    output logic [31:0] id_inst         
);

    localparam [31:0] NOP_INST = 32'h00000013;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc   <= 32'b0;
            id_inst <= NOP_INST;
        end else if (flush) begin
            id_pc   <= 32'b0;
            id_inst <= NOP_INST;
        end else if (en) begin
            id_pc   <= if_pc;
            id_inst <= if_inst;
        end
    end
endmodule