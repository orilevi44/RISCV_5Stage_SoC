`timescale 1ns / 1ps

/**
 * Fetch Stage Module
 * Responsibilities:
 * 1. Maintain the Program Counter (PC).
 * 2. Handle PC increments (PC+4) and Jumps/Branches.
 * 3. Synchronize the PC with the instruction fetched from memory.
 */
module fetch_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,             // Stall from Hazard Unit (1 = run, 0 = stall)
    input  logic        jump_sel,       // High if Branch/Jump is taken in later stages
    input  logic [31:0] jump_addr,      // Target address from Execute/Memory stage

    // Memory Interface
    output logic [31:0] icache_addr,    // Address sent to Instruction Memory
    input  logic [31:0] icache_instr,   // Instruction data coming back from memory
    input  logic        icache_ready,   // Logic high if memory is ready

    // Pipeline Outputs (to IF/ID Register)
    output logic [31:0] if_pc,          // The PC corresponding to if_instr
    output logic [31:0] if_instr,       // The fetched instruction
    output logic        if_stall        // Stall signal for the rest of the SoC
);

    // --- Internal Signals ---
    logic [31:0] current_fetch_pc;      // The PC currently being requested from RAM
    logic [31:0] next_pc;               // Calculated next PC value
    logic [31:0] pc_plus_4;
    logic [31:0] pc_delayed_q;          // PC of the instruction arriving NOW
    logic        pc_en;

    // 1. Next PC Logic
    assign pc_plus_4 = current_fetch_pc + 32'd4;
    
    // Select between sequential flow and Branch/Jump targets
    // Use '== 1'b1' to prevent X-propagation issues
    assign next_pc = (jump_sel === 1'b1) ? jump_addr : pc_plus_4;

    // 2. Control Logic
    assign pc_en    = (en === 1'b1) && (icache_ready === 1'b1);
    assign if_stall = !icache_ready;

    // 3. PC Register: Holds the address for the CURRENT fetch request
    pc_reg pc_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pc_en),
        .next_pc (next_pc),
        .pc_out  (current_fetch_pc)
    );

    // 4. Delay Register: Synchronizes PC with Instruction latency
    // Since memory takes 1 cycle, we delay the PC by 1 cycle to match the data.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_delayed_q <= 32'b0;
        end else if (pc_en) begin
            pc_delayed_q <= current_fetch_pc;
        end
    end

    // --- Output Assignments ---
    assign icache_addr = current_fetch_pc; // Address sent to Memory
    assign if_pc       = pc_delayed_q;     // Aligned PC sent to Decode stage
    assign if_instr    = icache_instr;     // Instruction sent to Decode stage

endmodule