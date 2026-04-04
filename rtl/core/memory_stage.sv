`timescale 1ns / 1ps

module memory_stage (
    // --- Data and Control Inputs from Register ---
    input  logic [31:0] mem_alu_result,      // Used as RAM Address
    input  logic [31:0] mem_write_data,      // Data to store in RAM (rs2)
    input  logic [31:0] mem_branch_target_in, // כתובת היעד שהגיעה מה-EX/MEM Register
    input  logic        mem_mem_read_en,     
    input  logic        mem_mem_write_en,    
    input  logic        mem_branch_en,       
    input  logic        mem_alu_zero,        
    input  logic [2:0]  mem_funct3,          
    
    // --- Data Memory (RAM) Interface ---
    output logic [31:0] ram_addr,            
    output logic [31:0] ram_wr_data,         
    output logic        ram_wr_en,           
    input  logic [31:0] ram_rd_data,         
    
    // --- Outputs to the rest of the CPU ---
    output logic [31:0] mem_read_data,       
    output logic [31:0] mem_branch_target_out, // הכתובת שנשלחת חזרה ל-Fetch Unit
    output logic        mem_branch_taken     
);

    /**
     * Branch Logic
     */
    always_comb begin
        case (mem_funct3)
            3'b000:  mem_branch_taken = mem_branch_en && mem_alu_zero;  // BEQ
            3'b001:  mem_branch_taken = mem_branch_en && !mem_alu_zero; // BNE
            default: mem_branch_taken = 1'b0;
        endcase
    end

    // העברת כתובת היעד הלאה
    assign mem_branch_target_out = mem_branch_target_in;

    // --- RAM Interface Mapping ---
    assign ram_addr      = mem_alu_result;
    assign ram_wr_data   = mem_write_data;
    assign ram_wr_en     = mem_mem_write_en;
    
    // --- Outputs ---
    assign mem_read_data = ram_rd_data;

endmodule