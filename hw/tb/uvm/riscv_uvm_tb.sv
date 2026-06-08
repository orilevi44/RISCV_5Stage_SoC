// ============================================================================
// Module      : riscv_uvm_tb (top-level UVM testbench)
// Description : Instantiates the SoC DUT, wires the virtual interface probes
//               to internal DUT signals, and launches the UVM test.
//
// Usage (Questa example):
//   vlog -sv -mfcu +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
//        hw/rtl/**/*.sv                                             \
//        hw/tb/uvm/riscv_if.sv                                      \
//        hw/tb/uvm/riscv_uvm_pkg.sv                                 \
//        hw/tb/uvm/riscv_uvm_tb.sv
//
//   vsim -sv_seed random +UVM_TESTNAME=riscv_alu_test riscv_uvm_tb
//   vsim -sv_seed random +UVM_TESTNAME=riscv_load_store_test riscv_uvm_tb
//
// VCS example:
//   vcs -sverilog -ntb_opts uvm-1.2 +incdir+<uvm>/src                \
//       hw/rtl/**/*.sv hw/tb/uvm/riscv_if.sv                          \
//       hw/tb/uvm/riscv_uvm_pkg.sv hw/tb/uvm/riscv_uvm_tb.sv         \
//       -o simv
//   ./simv +UVM_TESTNAME=riscv_alu_test
//
// Register-file hierarchy (probe path):
//   uut.u_core.u_decode_stage.reg_file_inst
//     .we         — write enable (1 cycle, posedge clk)
//     .write_reg  — destination register address [4:0]
//     .write_data — data to write [31:0]
// ============================================================================
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Compilation-unit scope imports.
// These must appear BEFORE the module keyword so that uvm_config_db,
// run_test(), and all UVM macros are visible inside the module body.
// With EDA Playground's "UVM 1.2" checkbox, uvm_pkg is pre-compiled;
// these lines simply bring its symbols into this compilation unit.
// ---------------------------------------------------------------------------
import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_uvm_pkg::*;

module riscv_uvm_tb;

    // -----------------------------------------------------------------------
    // Clock generation: 10 ns period (100 MHz)
    // -----------------------------------------------------------------------
    logic clk  = 1'b0;
    logic rst_n;                  // driven by UVM driver via force

    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Virtual interface instance
    // -----------------------------------------------------------------------
    riscv_if dut_if (.clk(clk), .rst_n(rst_n));

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    soc_top uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .soc_gpio_out(/* unused in UVM TB */),
        .soc_uart_tx (/* unused */),
        .soc_uart_rx (1'b1)    // idle UART line
    );

    // -----------------------------------------------------------------------
    // Connect the interface observation wires to internal DUT signals.
    // These are read-only from the interface perspective (assign, not force).
    //
    // The register file write port lives inside decode_stage; the WB stage
    // feeds write_reg, write_data, and we back into decode_stage for the
    // register file.  We tap the three signals directly on the register file
    // instance so we observe the actual write that commits to storage.
    // -----------------------------------------------------------------------
    assign dut_if.regfile_we    =
        uut.u_core.u_decode_stage.reg_file_inst.we;
    assign dut_if.regfile_waddr =
        uut.u_core.u_decode_stage.reg_file_inst.write_reg;
    assign dut_if.regfile_wdata =
        uut.u_core.u_decode_stage.reg_file_inst.write_data;

    // -----------------------------------------------------------------------
    // UVM configuration and test launch
    // -----------------------------------------------------------------------
    initial begin
        // Make the virtual interface available to all UVM components.
        uvm_config_db #(virtual riscv_if)::set(null, "uvm_test_top.*", "vif", dut_if);

        // Waveform dump (optional — comment out if not needed)
        $dumpfile("dump.vcd");
        $dumpvars(0, riscv_uvm_tb);

        run_test(); // Test name comes from +UVM_TESTNAME on the command line
    end

endmodule : riscv_uvm_tb
