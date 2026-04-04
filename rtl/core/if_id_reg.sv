`timescale 1ns / 1ps

module if_id_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,          // Clear on Control Hazard
    input  logic        en,             // Stall for Data Hazard

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