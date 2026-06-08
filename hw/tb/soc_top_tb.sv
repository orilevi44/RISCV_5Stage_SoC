`timescale 1ns / 1ps

module tb_soc_top();

    logic clk;
    logic rst_n;
    logic soc_uart_rx;
    logic soc_uart_tx;
    logic [31:0] soc_gpio_out;

    // DUT Instance
    soc_top uut (
        .clk(clk),
        .rst_n(rst_n),
        .soc_uart_rx(soc_uart_rx),
        .soc_uart_tx(soc_uart_tx),
        .soc_gpio_out(soc_gpio_out)
    );

    // -------------------------------------------------------------------------
    // Clock Generator — 100 MHz (period = 10 ns)
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // GPIO Decoder — prints a human-readable result every time GPIO changes.
    // Encoding (set by dcache_test.c):
    //   0x01 .. 0x08  → test N passed
    //   0xE1 .. 0xE8  → test N FAILED
    //   0xFF          → all tests passed
    //   anything else → raw value printed (other firmware / unexpected)
    // -------------------------------------------------------------------------
    always @(soc_gpio_out) begin
        case (soc_gpio_out)
            // --- Pass codes ---
            32'h01: $display("[%0t ns]  TEST 1 PASSED  (Cold miss -> allocate -> read hit)",          $time);
            32'h02: $display("[%0t ns]  TEST 2 PASSED  (Byte writes sb inside cached line)",          $time);
            32'h03: $display("[%0t ns]  TEST 3 PASSED  (Halfword writes sh inside cached line)",      $time);
            32'h04: $display("[%0t ns]  TEST 4 PASSED  (Full 4-word line fill + multi-word read)",    $time);
            32'h05: $display("[%0t ns]  TEST 5 PASSED  (Dirty eviction / conflict miss)",             $time);
            32'h06: $display("[%0t ns]  TEST 6 PASSED  (Write-back persisted to RAM after eviction)", $time);
            32'h07: $display("[%0t ns]  TEST 7 PASSED  (All 8 cache lines filled and verified)",      $time);
            32'h08: $display("[%0t ns]  TEST 8 PASSED  (Sustained read hit x16)",                    $time);
            32'hFF: $display("[%0t ns]  *** ALL TESTS PASSED ***  GPIO = 0xFF",                       $time);

            // --- Fail codes ---
            32'hE1: $display("[%0t ns]  TEST 1 FAILED  (Cold miss / allocate / read hit)",           $time);
            32'hE2: $display("[%0t ns]  TEST 2 FAILED  (Byte writes sb)",                            $time);
            32'hE3: $display("[%0t ns]  TEST 3 FAILED  (Halfword writes sh)",                        $time);
            32'hE4: $display("[%0t ns]  TEST 4 FAILED  (Full 4-word line fill)",                     $time);
            32'hE5: $display("[%0t ns]  TEST 5 FAILED  (Dirty eviction / conflict miss)",            $time);
            32'hE6: $display("[%0t ns]  TEST 6 FAILED  (Write-back to RAM after eviction)",          $time);
            32'hE7: $display("[%0t ns]  TEST 7 FAILED  (Sequential fill of all 8 lines)",            $time);
            32'hE8: $display("[%0t ns]  TEST 8 FAILED  (Sustained read hit)",                        $time);

            // --- Any other value (e.g. from other firmware) ---
            default: $display("[%0t ns]  GPIO = 0x%08X  (%0d decimal)",
                              $time, soc_gpio_out, soc_gpio_out);
        endcase
    end

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        rst_n      = 0;
        soc_uart_rx = 1;   // UART idle

        #100;
        rst_n = 1;
        $display("[%0t ns]  Reset released : CPU is running firmware...", $time);
        $display("------------------------------------------------------------");

        // Wait long enough for the CPU to execute all 8 tests.
        // Each cache miss takes ~7 cycles (WRITE_BACK=4 + FETCH=6 at worst).
        // 2 ms @ 100 MHz gives 200,000 cycles — more than enough.
        #2_000_000;

        $display("------------------------------------------------------------");
        $display("[%0t ns]  Simulation finished.", $time);
        $stop;
    end

endmodule