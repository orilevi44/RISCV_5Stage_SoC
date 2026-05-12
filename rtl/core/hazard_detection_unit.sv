`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Hazard Detection Unit
//
// Handles three hazard classes:
//   1. Branch/jump flush  — flushes IF/ID, ID/EX, EX/MEM on a taken branch.
//   2. Load-use stall     — stalls IF+ID and flushes ID/EX when an EX-stage
//                           load is followed immediately by a dependent inst.
//   3. UART wait-state    — when lbu/lw reaches MEM stage targeting the UART
//                           address window (0x3000-0x300F), one extra cycle is
//                           needed for uart_rdata_sync to settle.  The HDU
//                           asserts uart_stall for exactly ONE cycle; the
//                           uart_already_waited input (driven by a FF in
//                           riscv_core that captures uart_stall) clears it on
//                           the following cycle.
// ---------------------------------------------------------------------------

module hazard_detection_unit (
    // Load-use hazard inputs
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_mem_read_en,

    // Branch/jump taken
    input  logic        jump_branch_taken,

    // UART wait-state inputs
    input  logic        mem_mem_read_en,    // lbu/lw is in MEM stage
    input  logic [31:0] mem_alu_result,     // address being presented to bus
    input  logic        uart_already_waited,// high the cycle AFTER uart_stall fired

    // Standard pipeline control outputs
    output logic        if_pc_en,
    output logic        id_reg_en,
    output logic        id_ex_flush,
    output logic        if_id_flush,
    output logic        ex_mem_flush,

    // UART wait-state output — used by riscv_core to freeze/flush pipeline
    output logic        uart_stall
);

    // Detect a read whose target address falls in the UART window.
    // mem_alu_result[31:4] == 0x0000300 covers 0x3000-0x300F.
    logic uart_read_detected;
    assign uart_read_detected = mem_mem_read_en &&
                                (mem_alu_result[31:4] == 28'h0000_300);

    // Assert for exactly one cycle: high on first detection, cleared once
    // uart_already_waited (= previous uart_stall) goes high.
    assign uart_stall = uart_read_detected && !uart_already_waited;

    // -----------------------------------------------------------------------
    // Priority (highest → lowest):
    //   1. jump_branch_taken — hard flush of fetch/decode/execute
    //   2. uart_stall        — freeze everything ahead of MEM
    //   3. load-use          — stall fetch/decode, flush ID/EX bubble
    // -----------------------------------------------------------------------
    always_comb begin
        // Defaults: pipeline flows freely
        if_pc_en     = 1'b1;
        id_reg_en    = 1'b1;
        id_ex_flush  = 1'b0;
        if_id_flush  = 1'b0;
        ex_mem_flush = 1'b0;

        if (jump_branch_taken) begin
            // Kill the three instructions speculatively fetched after the branch.
            if_id_flush  = 1'b1;
            id_ex_flush  = 1'b1;
            ex_mem_flush = 1'b1;
        end
        else if (uart_stall) begin
            // Freeze the front-end.  riscv_core uses global_stall (= uart_stall)
            // to also freeze id_ex_reg and ex_mem_reg, and flushes mem_wb_reg
            // to insert a NOP into WB so the preceding instruction is not
            // written to the register file a second time on stall release.
            if_pc_en  = 1'b0;
            id_reg_en = 1'b0;
        end
        else if (ex_mem_read_en && (ex_rd_addr != 5'b0) &&
                 ((ex_rd_addr == id_rs1) || (ex_rd_addr == id_rs2))) begin
            // Classic load-use: stall fetch/decode, bubble decode/execute.
            if_pc_en    = 1'b0;
            id_reg_en   = 1'b0;
            id_ex_flush = 1'b1;
        end
    end

endmodule
