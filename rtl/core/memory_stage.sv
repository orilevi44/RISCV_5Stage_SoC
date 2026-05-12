`timescale 1ns / 1ps

// Memory Stage
// Evaluates branch conditions and formats the data returned by a load instruction.
// Does not directly access memory — the bus is driven by riscv_core connections.
module memory_stage (
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_write_data,
    input  logic [31:0] mem_branch_target_in,
    input  logic         mem_mem_read_en,     
    input  logic         mem_mem_write_en,    
    input  logic         mem_branch_en,       
    input  logic         mem_alu_zero,        
    input  logic [2:0]  mem_funct3,          
    
    input  logic [31:0] ram_rd_data, // Data coming from System Bus.
    
    output logic [31:0] mem_read_data,        
    output logic [31:0] mem_branch_target_out, 
    output logic         mem_branch_taken      
);

    logic [7:0]  byte_data;
    logic [15:0] half_data;

    assign byte_data = ram_rd_data[7:0];
    assign half_data = ram_rd_data[15:0];

    // Branch Evaluation — check whether funct3 condition matches the ALU output
    always_comb begin
        mem_branch_taken = 1'b0;
        if (mem_branch_en) begin
            case (mem_funct3)
                3'b000:  mem_branch_taken = mem_alu_zero;  // BEQ
                3'b001:  mem_branch_taken = !mem_alu_zero; // BNE
                default: mem_branch_taken = 1'b0;
            endcase
        end
    end

    assign mem_branch_target_out = mem_branch_target_in;

    // Load Formatting — zero-extend the raw bus data to the right width
    always_comb begin
        if (mem_mem_read_en) begin
            case (mem_funct3)
                3'b010:  mem_read_data = ram_rd_data;              // LW
                3'b100:  mem_read_data = {24'b0, byte_data};       // LBU
                3'b101:  mem_read_data = {16'b0, half_data};       // LHU
                default: mem_read_data = ram_rd_data;
            endcase
        end else begin
            mem_read_data = 32'b0;
        end
    end

endmodule