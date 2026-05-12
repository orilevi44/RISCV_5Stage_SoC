`timescale 1ns / 1ps

// CSR Unit — Control and Status Registers
// Implements two read-only performance counters:
//   mcycle   (0xB00/0xB80) — total clock cycles since reset
//   minstret (0xB02/0xB82) — instructions retired (completed) since reset
// Both are 64-bit, split into low/high 32-bit halves.
module csr_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        inst_retired,
    input  logic        csr_we,          // Kept for future writable CSRs
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    output logic [31:0] csr_rdata
);

    logic [63:0] mcycle;
    logic [63:0] minstret;

    wire [31:0] mcycle_low  = mcycle[31:0];
    wire [31:0] mcycle_high = mcycle[63:32];
    wire [31:0] minst_low   = minstret[31:0];
    wire [31:0] minst_high  = minstret[63:32];

    // 1. Cycle Counter (Hardware Controlled)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mcycle <= 64'b0;
        else        mcycle <= mcycle + 1;
    end

    // 2. Instruction Counter (Hardware Controlled)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          minstret <= 64'b0;
        else if (inst_retired) minstret <= minstret + 1;
    end

    // 3. CSR Read Logic
    always_comb begin
        case (csr_addr)
            12'hb00: csr_rdata = mcycle_low;
            12'hb80: csr_rdata = mcycle_high;
            12'hb02: csr_rdata = minst_low;
            12'hb82: csr_rdata = minst_high;
            default: csr_rdata = 32'b0;
        endcase
    end

    // Note: The explicit write block for mcycle/minstret has been removed.
    // These specific performance counters are now safely Read-Only to prevent
    // accidental resets during 'csrr' reads.

endmodule