`timescale 1ns / 1ps

// CSR Unit — Control and Status Registers
// Implements read-only performance counters and interrupt management registers.
module csr_unit (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Hardware Counters Interface ---
    input  logic        inst_retired,
    
    // --- Software Interface (CSR Instructions) ---
    input  logic        csr_we,          // Write enable from control unit
    input  logic [11:0] csr_addr,        // CSR address
    input  logic [31:0] csr_wdata,       // Data to write into CSR
    output logic [31:0] csr_rdata,       // Data read from CSR
    
    // --- Hardware Interrupt Interface ---
    input  logic [31:0] current_pc,      // Current PC to save on trap
    input  logic        ext_intr,        // External interrupt request from PIC
    input  logic        mret_exec,       // Signal indicating 'mret' instruction executed
    
    // --- Outputs to CPU (Control Unit & PC Mux) ---
    output logic        take_trap,       // High when CPU must jump to ISR
    output logic [31:0] trap_target,     // The ISR address (mtvec)
    output logic [31:0] epc_out          // The return address (mepc)
);

    // --- Performance Counters ---
    logic [63:0] mcycle;
    logic [63:0] minstret;

    wire [31:0] mcycle_low  = mcycle[31:0];
    wire [31:0] mcycle_high = mcycle[63:32];
    wire [31:0] minst_low   = minstret[31:0];
    wire [31:0] minst_high  = minstret[63:32];

    // --- Interrupt Registers (RISC-V Standard Addresses) ---
    // 0x300: mstatus (Machine Status) -> bit 3 is MIE, bit 7 is MPIE
    // 0x305: mtvec   (Machine Trap-Vector Base-Address)
    // 0x341: mepc    (Machine Exception Program Counter)
    logic [31:0] mstatus; 
    logic [31:0] mtvec;   
    logic [31:0] mepc;    

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

    // 3. CSR Write Logic & Interrupt Hardware State Machine
    // Hardware traps and returns take priority over software writes.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus <= 32'b0;
            mtvec   <= 32'b0;
            mepc    <= 32'b0;
        end
        else begin
            // --- Trap Taken (Interrupt Occurred) ---
            // If external interrupt is high AND Machine Interrupt Enable (MIE) is 1
            if (ext_intr && mstatus[3]) begin 
                mstatus[7] <= mstatus[3]; // Save MIE into MPIE (Machine Previous Interrupt Enable)
                mstatus[3] <= 1'b0;       // Disable further interrupts (MIE = 0)
                mepc       <= current_pc; // Save the PC of the interrupted instruction
            end
            
            // --- Return from Trap (MRET Executed) ---
            else if (mret_exec) begin
                mstatus[3] <= mstatus[7]; // Restore MIE from MPIE
                mstatus[7] <= 1'b1;       // Set MPIE to 1 (default standard behavior)
            end
            
            // --- Software Write (CSRW instructions) ---
            else if (csr_we) begin
                case (csr_addr)
                    12'h300: mstatus <= csr_wdata;
                    12'h305: mtvec   <= csr_wdata;
                    12'h341: mepc    <= csr_wdata;
                    // Counters are explicitly NOT written here (Read-Only)
                    default: ; 
                endcase
            end
        end
    end

    // 4. CSR Read Logic
    always_comb begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'hb00: csr_rdata = mcycle_low;
            12'hb80: csr_rdata = mcycle_high;
            12'hb02: csr_rdata = minst_low;
            12'hb82: csr_rdata = minst_high;
            default: csr_rdata = 32'b0;
        endcase
    end

    // 5. Outputs to PC Mux and Control Unit
    // Tell the CPU to take a trap immediately if an interrupt is pending and enabled
    assign take_trap   = (ext_intr && mstatus[3]);
    assign trap_target = mtvec;
    assign epc_out     = mepc;

endmodule