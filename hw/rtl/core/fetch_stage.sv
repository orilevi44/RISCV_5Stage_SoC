`timescale 1ns / 1ps

// Fetch Stage
// Reads the next instruction from ROM using the Program Counter (PC).
// Handles jumps (redirect PC) and stalls (freeze PC).
module fetch_stage (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         en,             // Stall signal (1 = Go, 0 = Wait)
    input  logic         jump_sel,       // High if Branch/Jump is taken
    input  logic [31:0]  jump_addr,      // Target address

    // Instruction Memory Interface
    output logic [31:0]  icache_addr,    
    input  logic [31:0]  icache_instr,   
    input  logic         icache_ready,   

    // Pipeline Stage Outputs
    output logic [31:0]  if_pc,          
    output logic [31:0]  if_instr,       
    output logic         if_stall        
);

    logic [31:0] current_pc;
    logic [31:0] next_pc;

    // 1. Next PC Logic (The Multiplexer)
    always_comb begin


        if (jump_sel) begin
            next_pc = jump_addr;
        end else if (en) begin
            next_pc = current_pc + 32'd4;
        end else begin
            next_pc = current_pc; // Stall: keep PC unchanged
        end
    end

    // 2. Control Logic
    // Critical: on a jump, always allow PC update even if the pipeline is stalled
    logic pc_update_en;
    assign pc_update_en = (icache_ready&& en ) || jump_sel; 
    
    assign if_stall     = !icache_ready;

    // 3. PC Register
    pc_reg pc_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pc_update_en),
        .next_pc (next_pc),
        .pc_out  (current_pc)
    );

    // Outputs
    assign icache_addr = current_pc;  
    assign if_pc       = current_pc; 
    assign if_instr    = icache_instr; 

endmodule