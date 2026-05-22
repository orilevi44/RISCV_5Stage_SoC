`timescale 1ns / 1ps
// =============================================================================
// Echo Test: sends 'A', 'B', 'C' and verifies each echo.
// Output is intentionally minimal — only PASS / FAIL lines.
// =============================================================================

module echo_test_tb ();

    localparam CLK_FREQ   = 100_000_000;
    localparam BAUD_RATE  = 12_500_000;
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;  // 8 clocks per bit
    localparam TIMEOUT_CY = 200_000;                // 2 ms @ 100 MHz

    logic        clk, rst_n;
    logic        uart_tx, uart_rx_pin;
    logic [31:0] gpio_out;

    // Captured echo bytes and a count of received frames
    int          echo_count = 0;
    logic [7:0]  echo_buf[3];   // stores up to 3 echoes
    int          test_ok   = 1; // 0 → at least one failure

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    soc_top uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .soc_gpio_out(gpio_out),
        .soc_uart_tx (uart_tx),
        .soc_uart_rx (uart_rx_pin)
    );

    // -------------------------------------------------------------------------
    // Clock  (10 ns period = 100 MHz)
    // -------------------------------------------------------------------------
    initial begin clk = 0; forever #5 clk = ~clk; end

    // -------------------------------------------------------------------------
    // Reset + waveform dump + ROM load
    // Hex file is passed at runtime: +HEX_FILE=sim/hex/echo.hex
    // -------------------------------------------------------------------------
    initial begin
        string hex_file;
        $dumpfile("sim/waves.fst");
        $dumpvars(0, echo_test_tb);
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        if ($value$plusargs("HEX_FILE=%s", hex_file))
            $readmemh(hex_file, uut.u_rom.mem);
        else begin
            $display("[ERROR] No HEX_FILE provided. Use +HEX_FILE=sim/hex/echo.hex");
            $finish;
        end
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
    end

    // -------------------------------------------------------------------------
    // send_byte — drives one UART frame onto uart_rx_pin (LSB-first, 8N1)
    // -------------------------------------------------------------------------
    task automatic send_byte;
        input [7:0] data;
        integer i;
        begin
            @(negedge clk); uart_rx_pin = 1'b0;          // start bit
            repeat (BIT_PERIOD) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk); uart_rx_pin = data[i];   // data bits
                repeat (BIT_PERIOD) @(posedge clk);
            end
            @(negedge clk); uart_rx_pin = 1'b1;          // stop bit
            repeat (BIT_PERIOD) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // wait_and_check — waits up to TIMEOUT_CY cycles for echo #idx,
    // then compares against 'expected' and prints PASS / FAIL.
    // -------------------------------------------------------------------------
    task automatic wait_and_check;
        input [7:0]  expected;
        input integer idx;
        integer cy;
        begin
            cy = 0;
            while (echo_count <= idx && cy < TIMEOUT_CY) begin
                @(posedge clk);
                cy = cy + 1;
            end

            if (cy >= TIMEOUT_CY) begin
                $display("[FAIL] Echo %0d ('%c') — TIMEOUT after %0d cycles",
                         idx+1, expected, TIMEOUT_CY);
                test_ok = 0;
            end else if (echo_buf[idx] === expected) begin
                $display("[PASS] Echo %0d: sent '%c' (0x%02h), received '%c' (0x%02h)  ✓",
                         idx+1,
                         expected, expected,
                         echo_buf[idx], echo_buf[idx]);
            end else begin
                $display("[FAIL] Echo %0d: sent '%c' (0x%02h), received '%c' (0x%02h)",
                         idx+1,
                         expected, expected,
                         echo_buf[idx], echo_buf[idx]);
                test_ok = 0;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Echo monitor — samples uart_tx and reconstructs bytes (LSB-first, 8N1)
    // -------------------------------------------------------------------------
    initial begin : echo_monitor
        integer i;
        logic [7:0] b;
        wait (rst_n === 1'b1);
        forever begin
            @(negedge uart_tx);                                    // start bit
            repeat (BIT_PERIOD + BIT_PERIOD/2) @(posedge clk);    // centre of bit 0
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = uart_tx;
                if (i < 7) repeat (BIT_PERIOD) @(posedge clk);
            end
            if (echo_count < 3) echo_buf[echo_count] = b;
            echo_count = echo_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin : main_test
        wait (rst_n === 1'b1);
        repeat (200) @(posedge clk);   // let CPU settle after reset

        $display("");
        $display("===========================================");
        $display("       UART Echo Test: 'A'  'B'  'C'");
        $display("===========================================");

        send_byte("A");  wait_and_check("A", 0);
        send_byte("B");  wait_and_check("B", 1);
        send_byte("C");  wait_and_check("C", 2);

        $display("-------------------------------------------");
        if (test_ok)
            $display("  RESULT:  ALL TESTS PASSED  ✓");
        else
            $display("  RESULT:  ONE OR MORE TESTS FAILED  ✗");
        $display("===========================================");
        $display("");
        $finish;
    end

endmodule
