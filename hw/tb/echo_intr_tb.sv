`timescale 1ns / 1ps

module echo_intr_tb ();

    localparam CLK_FREQ   = 100_000_000;
    localparam BAUD_RATE  = 12_500_000;
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;
    localparam TIMEOUT_CY = 200_000;                

    logic        clk, rst_n;
    logic        uart_tx, uart_rx_pin;
    logic [31:0] gpio_out;

    int          echo_count = 0;
    logic [7:0]  echo_buf[3];   
    int          test_ok   = 1; 

    // --- DUT Instantiation ---
    soc_top uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .soc_gpio_out(gpio_out),
        .soc_uart_tx (uart_tx),
        .soc_uart_rx (uart_rx_pin)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        string hex_file;
        $dumpfile("sim/waves.fst");
        $dumpvars(0, echo_intr_tb);
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        
        if ($value$plusargs("HEX_FILE=%s", hex_file))
            $readmemh(hex_file, uut.u_rom.mem);
        else begin
            $display("[ERROR] No HEX_FILE provided. Use +HEX_FILE=sim/hex/echo_intr.hex");
            $finish;
        end
        
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
    end

    // --- Hardware Interrupt Monitor ---
    initial begin
        wait (rst_n === 1'b1);
        forever begin
            @(posedge clk);
            if (uut.u_core.ext_intr === 1'b1) begin
                $display("  --> [HARDWARE] PIC triggered ext_intr!");
                
                // FIXED: Now waiting for the correct ISR address (0x20)
                wait (uut.u_core.if_pc == 32'h0000_0020);
                $display("  --> [HARDWARE] CPU paused main loop and jumped to ISR at 0x20!");
                
                wait (uut.u_core.ext_intr === 1'b0);
                $display("  --> [HARDWARE] UART IRQ cleared by CPU read.");
            end
        end
    end

    task automatic send_byte;
        input [7:0] data;
        integer i;
        begin
            @(negedge clk); uart_rx_pin = 1'b0;
            repeat (BIT_PERIOD) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk); uart_rx_pin = data[i];
                repeat (BIT_PERIOD) @(posedge clk);
            end
            @(negedge clk); uart_rx_pin = 1'b1;
            repeat (BIT_PERIOD) @(posedge clk);
        end
    endtask

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
                $display("[FAIL] Echo %0d ('%c') — TIMEOUT", idx+1, expected);
                test_ok = 0;
            end else if (echo_buf[idx] === expected) begin
                $display("[PASS] Echo %0d: sent '%c', received '%c'  OK", idx+1, expected, echo_buf[idx]);
            end else begin
                $display("[FAIL] Echo %0d: sent '%c', received '%c'", idx+1, expected, echo_buf[idx]);
                test_ok = 0;
            end
        end
    endtask

    initial begin : echo_monitor
        integer i;
        logic [7:0] b;
        wait (rst_n === 1'b1);
        forever begin
            @(negedge uart_tx);
            repeat (BIT_PERIOD + BIT_PERIOD/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = uart_tx;
                if (i < 7) repeat (BIT_PERIOD) @(posedge clk);
            end
            if (echo_count < 3) echo_buf[echo_count] = b;
            echo_count = echo_count + 1;
        end
    end

    initial begin : main_test
        wait (rst_n === 1'b1);
        repeat (200) @(posedge clk);

        $display("\n===========================================");
        $display("   UART Interrupt Echo Test: 'X'  'Y'  'Z'");
        $display("===========================================");

        send_byte("X");  wait_and_check("X", 0);
        send_byte("Y");  wait_and_check("Y", 1);
        send_byte("Z");  wait_and_check("Z", 2);

        $display("-------------------------------------------");
        if (test_ok)
            $display("  RESULT:  ALL INTERRUPT TESTS PASSED!");
        else
            $display("  RESULT:  TEST FAILED!");
        $display("===========================================\n");
        $finish;
    end

endmodule