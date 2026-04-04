`timescale 1ns / 1ps

/**
 * Memory Stage
 * -------------------
 * Final corrected version with Icarus Verilog bit-selection fixes.
 */
module memory_stage (
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_write_data,
    input  logic [31:0] mem_branch_target_in,
    input  logic        mem_mem_read_en,     
    input  logic        mem_mem_write_en,    
    input  logic        mem_branch_en,       
    input  logic        mem_alu_zero,        
    input  logic [2:0]  mem_funct3,          
    
    output logic [31:0] ram_addr,            
    output logic [31:0] ram_wr_data,         
    output logic        ram_wr_en,           
    input  logic [31:0] ram_rd_data,         
    
    output logic [31:0] mem_read_data,       
    output logic [31:0] mem_branch_target_out, 
    output logic        mem_branch_taken      
);

    // Local wires to avoid "constant select" errors in Icarus Verilog
    logic        lsb_bit;
    logic [7:0]  byte_data;
    logic [15:0] half_data;
    logic        byte_sign;
    logic        half_sign;

    assign lsb_bit   = mem_alu_result[0];
    assign byte_data = ram_rd_data[7:0];
    assign half_data = ram_rd_data[15:0];
    assign byte_sign = ram_rd_data[7];
    assign half_sign = ram_rd_data[15];

    /**
     * 1. Branch Logic Evaluation
     */
    always_comb begin
        if (mem_branch_en) begin
            case (mem_funct3)
                3'b000:  mem_branch_taken = mem_alu_zero;       // BEQ
                3'b001:  mem_branch_taken = !mem_alu_zero;      // BNE
                3'b100:  mem_branch_taken = lsb_bit;            // BLT
                3'b101:  mem_branch_taken = !lsb_bit;           // BGE
                3'b110:  mem_branch_taken = lsb_bit;            // BLTU
                3'b111:  mem_branch_taken = !lsb_bit;           // BGEU
                default: mem_branch_taken = 1'b0;
            endcase
        end else begin
            mem_branch_taken = 1'b0;
        end
    end

    assign mem_branch_target_out = mem_branch_target_in;

    assign ram_addr    = mem_alu_result;
    assign ram_wr_data = mem_write_data;
    assign ram_wr_en   = mem_mem_write_en;
    
    /**
     * 2. Load Data Formatting
     */
    always_comb begin
        if (mem_mem_read_en) begin
            case (mem_funct3)
                3'b000:  mem_read_data = {{24{byte_sign}}, byte_data}; // LB
                3'b001:  mem_read_data = {{16{half_sign}}, half_data}; // LH
                3'b010:  mem_read_data = ram_rd_data;                  // LW
                3'b100:  mem_read_data = {24'b0, byte_data};           // LBU
                3'b101:  mem_read_data = {16'b0, half_data};           // LHU
                default: mem_read_data = ram_rd_data;
            endcase
        end else begin
            mem_read_data = 32'b0;
        end
    end

endmodule