// ============================================================================
// Interface : riscv_if
// Description : Virtual interface that bridges the UVM agent to the DUT.
//
//   Ports (driven by the TB top module, riscv_uvm_tb):
//     clk, rst_n  — system clock and active-low reset
//
//   Probed signals (connected via assign in riscv_uvm_tb):
//     regfile_we, regfile_waddr, regfile_wdata
//       — register-file write port from the WB stage
//         hierarchy: uut.u_core.u_decode_stage.reg_file_inst.{we,write_reg,write_data}
//
//   The clocking block (monitor_cb) samples signals 1-step after the active
//   clock edge so the monitor never races with combinational settling.
// ============================================================================
`timescale 1ns/1ps

interface riscv_if (
    input logic clk,
    input logic rst_n
);

    // -----------------------------------------------------------------------
    // Register-file write-port observation
    // These nets are driven by assign statements in the TB top module.
    // -----------------------------------------------------------------------
    logic        regfile_we;
    logic [4:0]  regfile_waddr;
    logic [31:0] regfile_wdata;

    // -----------------------------------------------------------------------
    // Clocking block: monitor samples posedge, 1-step after to avoid races
    // -----------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input rst_n;
        input regfile_we;
        input regfile_waddr;
        input regfile_wdata;
    endclocking

endinterface : riscv_if
