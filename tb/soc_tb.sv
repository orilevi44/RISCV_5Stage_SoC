`timescale 1ns / 1ps

// =============================================================================
// SoC Testbench — Enhanced UART Debug Edition
// =============================================================================
// Debug monitors added:
//   [BUS]    — every read/write to the UART address window (0x3000-0x300F)
//   [REGWB]  — every write to x6 (t1) or x7 (t2) from the WB stage
//   [BRANCH] — every taken branch/jump (tells us which loop the CPU is in)
//   [STORE]  — explicit flag whenever sb/sw lands on address 0x3000
//   All blocks also dump the live UART internal state (tx_busy, rx_valid_sticky,
//   rx_data_reg) so we can correlate CPU decisions with peripheral truth.
// =============================================================================

module soc_tb ();

    localparam CLK_FREQ   = 100_000_000;
    localparam BAUD_RATE  = 12_500_000;
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;  // = 8 clocks

    logic        clk, rst_n;
    logic        uart_tx, uart_rx_pin;
    logic [31:0] gpio_out;

    int          received_count = 0;
    logic [7:0]  captured_byte;
    bit          smart_debug_en = 0;

    // =========================================================================
    // DUT
    // =========================================================================
    soc_top uut (
        .clk(clk), .rst_n(rst_n),
        .soc_gpio_out(gpio_out),
        .soc_uart_tx(uart_tx),
        .soc_uart_rx(uart_rx_pin)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // Reset + Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("sim/waves.fst");
        $dumpvars(0, soc_tb);
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        $readmemh("sim/program.hex", uut.u_rom.mem);
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
        $display("[%0t] [TB] Reset released.", $time);
    end

    // =========================================================================
    // Helper macros — shorthand for frequently-used hierarchy paths
    // =========================================================================
    // Register file (committed, post-WB values)
    `define REGS    uut.u_core.u_decode_stage.reg_file_inst.registers
    // UART peripheral internals
    `define UART    uut.u_uart
    // Core pipeline signals
    `define CORE    uut.u_core

    // =========================================================================
    // Shared UART-state printer task
    // Called by every debug block so every message carries the same context.
    // =========================================================================
    task automatic print_uart_state;
        $display("   [UART-HW] rx_valid_sticky=%b  rx_data_reg=0x%02h  tx_busy=%b",
                 `UART.rx_valid_sticky,
                 `UART.rx_data_reg,
                 `UART.tx_busy);
        $display("   [REGS]    x6/t1=0x%08h  x7/t2=0x%08h",
                 `REGS[6], `REGS[7]);
    endtask

    // =========================================================================
    // [BUS] UART Bus Monitor
    // Fires every cycle a UART-range address is read or written.
    // Covers:
    //   0x3000 — RX data / TX data (lbu reads, sb writes)
    //   0x3004 — status register   (rx_valid[0], tx_busy[1])
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst_n && smart_debug_en) begin

            // Detect any bus access to 0x3000–0x300F
            if ((`CORE.data_mem_rd_en || `CORE.data_mem_wr_en) &&
                (`CORE.data_mem_addr[15:4] == 12'h300)) begin

                $display("\n=== [BUS] t=%0t ============================================", $time);
                $display("   [PC]    IF_PC=0x%08h", `CORE.if_pc);

                // ---- READ -------------------------------------------------------
                if (`CORE.data_mem_rd_en) begin
                    $display("   [READ]  Addr=0x%08h  DataReturned=0x%08h",
                             `CORE.data_mem_addr,
                             `CORE.data_mem_rd_data);

                    // Decode which register this read is targeting (from status bits)
                    if (`CORE.data_mem_addr[3:0] == 4'h4) begin
                        // Reading the status register — decode fields directly
                        $display("   [STATUS-DECODE] rx_valid(bit0)=%b  tx_busy(bit1)=%b   (raw=0x%08h)",
                                 `CORE.data_mem_rd_data[0],
                                 `CORE.data_mem_rd_data[1],
                                 `CORE.data_mem_rd_data);
                    end else begin
                        $display("   [DATA-READ] RX byte from 0x3000 = 0x%02h ('%c')",
                                 `CORE.data_mem_rd_data[7:0],
                                 `CORE.data_mem_rd_data[7:0]);
                    end

                    // Stall machine state
                    $display("   [STALL] uart_stall=%b  wait_q=%b  global_stall=%b",
                             `CORE.uart_stall,
                             `CORE.uart_wait_cycle_q,
                             `CORE.global_stall);
                end

                // ---- WRITE ------------------------------------------------------
                if (`CORE.data_mem_wr_en) begin
                    $display("   [WRITE] Addr=0x%08h  DataWritten=0x%08h  byte='%c'",
                             `CORE.data_mem_addr,
                             `CORE.data_mem_wr_data,
                             `CORE.data_mem_wr_data[7:0]);
                    if (`CORE.data_mem_addr[3:0] == 4'h0)
                        $display("   [TX-TRIGGER] >>> SB to 0x3000 detected — UART TX should fire!");
                end

                // Always print peripheral truth + live register values
                print_uart_state();
                $display("============================================================");
            end
        end
    end

    // =========================================================================
    // [REGWB] Register Writeback Monitor
    // Fires whenever the WB stage commits a value to x6 (t1) or x7 (t2).
    // This catches ANDI results, LBU loads, and any other instruction that
    // updates these registers, letting us verify the CPU saw the right bits.
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst_n && smart_debug_en) begin
            if (`CORE.wb_reg_write_en &&
                (`CORE.wb_rd_addr == 5'd6 || `CORE.wb_rd_addr == 5'd7)) begin

                    $display("\n--- [REGWB] t=%0t ---", $time);
                $display("   Committing: x%0d = 0x%08h  (source: %s)",
                         `CORE.wb_rd_addr,
                         `CORE.wb_final_data,
                         `CORE.wb_mem_to_reg_sel ? "MEM(load)" : "ALU/imm");

                // If writing t1 (x6), interpret as potential ANDI/branch mask
                if (`CORE.wb_rd_addr == 5'd6) begin
                    $display("   [t1-MASK]  bit0(rx_valid)=%b  bit1(tx_busy)=%b",
                             `CORE.wb_final_data[0],
                             `CORE.wb_final_data[1]);
                end

                // Show live peripheral state alongside so we can check if CPU
                // received the right value from the UART register.
                print_uart_state();
                $display("-----------------------------------");
            end
        end
    end

    // =========================================================================
    // [BRANCH] Branch / Jump Monitor
    // Fires every cycle a taken branch or JAL/JALR resolves in the MEM stage.
    // Tells us which loop the CPU believes it is in:
    //   • Jumping backward → still polling (wait_rx or wait_tx)
    //   • Jumping forward  → loop exited
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst_n && smart_debug_en) begin
            if (`CORE.actual_jump) begin
                $display("\n--- [BRANCH] t=%0t ---", $time);
                $display("   Branch/Jump TAKEN → target PC=0x%08h",
                         `CORE.final_branch_addr);
                $display("   (mem_branch_taken=%b  mem_jal_en=%b  mem_jalr_en=%b)",
                         `CORE.mem_branch_taken,
                         `CORE.mem_jal_en,
                         `CORE.mem_jalr_en);
                // Print current register snapshot to show what condition fired
                $display("   [REGS] x6/t1=0x%08h  x7/t2=0x%08h",
                         `REGS[6], `REGS[7]);
                $display("   [UART-HW] rx_valid_sticky=%b  tx_busy=%b",
                         `UART.rx_valid_sticky, `UART.tx_busy);
                $display("-----------------------------------");
            end
        end
    end

    // =========================================================================
    // [STORE] Explicit SB/SW to 0x3000 trap
    // This is a focused alarm: if a write reaches 0x3000 but tx_busy is still
    // high, the UART will silently drop it — flag that scenario loudly.
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst_n && smart_debug_en) begin
            if (`CORE.data_mem_wr_en &&
                (`CORE.data_mem_addr == 32'h0000_3000)) begin

                $display("\n!!! [STORE-0x3000] t=%0t — CPU writing TX data !!!", $time);
                $display("    Byte: 0x%02h ('%c')",
                         `CORE.data_mem_wr_data[7:0],
                         `CORE.data_mem_wr_data[7:0]);
                if (`UART.tx_busy)
                    $display("    *** WARNING: tx_busy=1 — UART will IGNORE this write! ***");
                else
                    $display("    tx_busy=0 — TX should accept and begin transmitting.");
                $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            end
        end
    end

    // =========================================================================
    // Byte Injection Task
    // =========================================================================
    task automatic send_byte;
        input [7:0] data;
        integer i;
        begin
            $display("[%0t] [TB-TX] >>> Sending: 0x%02h ('%c')", $time, data, data);
            @(negedge clk); uart_rx_pin = 1'b0;          // Start bit
            repeat (BIT_PERIOD) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk); uart_rx_pin = data[i];   // Data bits LSB-first
                repeat (BIT_PERIOD) @(posedge clk);
            end
            @(negedge clk); uart_rx_pin = 1'b1;          // Stop bit
            repeat (BIT_PERIOD) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Echo Wait Task (with timeout)
    // =========================================================================
    task automatic wait_for_echo;
        input integer j;
        input [7:0]  ch;
        begin
            fork
                begin
                    wait (received_count == j + 1);
                    $display("[%0t] [TB] ✓ Echo %0d verified: 0x%02h ('%c')",
                             $time, j+1, ch, ch);
                    smart_debug_en = 0;
                end
                begin
                    #500_000;
                    $display("[%0t] [TB] TIMEOUT — no echo received within 500 µs.", $time);
                    // Dump final CPU and UART state before dying
                    $display("[TIMEOUT-DUMP] IF_PC=0x%08h", `CORE.if_pc);
                    $display("[TIMEOUT-DUMP] x6/t1=0x%08h  x7/t2=0x%08h",
                             `REGS[6], `REGS[7]);
                    $display("[TIMEOUT-DUMP] rx_valid_sticky=%b  rx_data_reg=0x%02h  tx_busy=%b",
                             `UART.rx_valid_sticky, `UART.rx_data_reg, `UART.tx_busy);
                    $display("[TIMEOUT-DUMP] data_mem_addr=0x%08h  rd_en=%b  wr_en=%b",
                             `CORE.data_mem_addr,
                             `CORE.data_mem_rd_en,
                             `CORE.data_mem_wr_en);
                    $finish;
                end
            join_any
            disable fork;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin : main_test
        wait (rst_n === 1'b1);
        repeat (200) @(posedge clk);   // let CPU settle after reset

        send_byte("A");
        // Enable debug immediately after injection so we catch all CPU decisions
        // about the newly-arrived byte.
        smart_debug_en = 1;
        wait_for_echo(0, "A");

        $finish;
    end

    // =========================================================================
    // Echo Capture (monitors UART TX pin for incoming serial frames)
    // =========================================================================
    initial begin : echo_monitor
        integer i;
        wait (rst_n === 1'b1);
        forever begin
            @(negedge uart_tx);                               // Wait for start bit
            repeat (BIT_PERIOD + BIT_PERIOD/2) @(posedge clk); // Sample mid-first-bit
            for (i = 0; i < 8; i = i + 1) begin
                captured_byte[i] = uart_tx;
                if (i < 7) repeat (BIT_PERIOD) @(posedge clk);
            end
            $display("[%0t] [ECHO-RX] Received byte: 0x%02h ('%c')",
                     $time, captured_byte, captured_byte);
            received_count = received_count + 1;
        end
    end

endmodule
