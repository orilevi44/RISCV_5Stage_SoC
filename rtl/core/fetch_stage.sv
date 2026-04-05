`timescale 1ns / 1ps

/**
 * Fetch Stage
 * -----------
 * Manages the Program Counter (PC) and interfaces with Instruction Memory.
 * Updated for Asynchronous ROM timing.
 */
module fetch_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,             // Stall signal from Hazard Unit
    input  logic        jump_sel,       // High if Branch/Jump is taken
    input  logic [31:0] jump_addr,      // Target address from MEM stage

    // Instruction Memory Interface
    output logic [31:0] icache_addr,    
    input  logic [31:0] icache_instr,   
    input  logic        icache_ready,   

    // Pipeline Stage Outputs
    output logic [31:0] if_pc,          
    output logic [31:0] if_instr,       
    output logic        if_stall        
);

    // --- Internal Signals ---
    logic [31:0] current_fetch_pc;
    logic [31:0] next_pc;
    logic [31:0] pc_plus_4;
    logic        pc_en;

    // 1. Next PC Logic
    assign pc_plus_4 = current_fetch_pc + 32'd4;
    
    // PC Multiplexer with explicit priority for jump targets
    always_comb begin
        if (jump_sel === 1'b1) begin
            next_pc = jump_addr;
        end else if (en === 1'b1) begin
            next_pc = pc_plus_4;
        end else begin
            next_pc = current_fetch_pc; // Maintain current PC during stall
        end
    end

    // 2. Control Logic
    // PC updates if memory is ready AND (Hazard Unit allows it OR a jump is occurring)
    assign pc_en    = icache_ready && (en || jump_sel);
    assign if_stall = !icache_ready;

    // 3. PC Register Instance
    pc_reg pc_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pc_en),
        .next_pc (next_pc),
        .pc_out  (current_fetch_pc)
    );

    // --- Output Assignments ---
    // With an async ROM, we directly ask for the current PC's instruction
    assign icache_addr = current_fetch_pc;  
    assign if_pc       = current_fetch_pc; 
    assign if_instr    = icache_instr; 

endmodule