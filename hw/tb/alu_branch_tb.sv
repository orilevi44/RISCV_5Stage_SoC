`timescale 1ns/1ps


module alu_branch_tb ();

    localparam CLK_FREQ   = 100_000_000;
    localparam TIMEOUT_CY = 200_000;     // 2 ms @ 100 MHz

    logic        clk, rst_n;
    logic        uart_tx, uart_rx_pin;
    logic [31:0] gpio_out;
    logic        test_ok   = 1; // 0 → at least one failure

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
    // Hex file is passed at runtime: +HEX_FILE=sim/hex/alu_branch.hex
    // -------------------------------------------------------------------------
    initial begin
        string hex_file;
        $dumpfile("sim/waves.fst");
        $dumpvars(0, alu_branch_tb);
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
        repeat (200) @(posedge clk);
        if ($value$plusargs("HEX_FILE=%s", hex_file))
            $readmemh(hex_file, uut.u_rom.mem);
        else begin
            $display("[ERROR] No HEX_FILE provided. Use +HEX_FILE=sim/hex/alu_branch.hex");
            $finish;
        end
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
     end

     //--- main test sequence --- 
     initial begin

        wait (rst_n ==1); 
        repeat (200) @(posedge clk);   // let CPU settle after reset

        $display("===========================================");
        $display("        ALU Branching Unit Test");
        $display("===========================================");

        // Check GPIO outputs for each test case
        check_gpio(32'd3, "Test 1: BLT false (not taken)");  
        check_gpio(32'd5, "Test 2: BEQ taken");

        $display("-------------------------------------------");
    
        if (test_ok)
            $display("  RESULT:  ALL TESTS PASSED ");
        else
            $display("  RESULT:  ONE OR MORE TESTS FAILED ");
        $display("===========================================");
        
        $finish; 
    end


        //  --- check_gpio task ---  
    task automatic check_gpio;
        input [31:0] expected;
        input string test_name;
        integer timeout;
        begin
            timeout = 0;
            // wait until GPIO matches expected value or timeout expires
            while (gpio_out !== expected && timeout < TIMEOUT_CY) begin
                @(posedge clk);
                timeout++;
            end
            if (gpio_out === expected )
                $display("[PASS] %s = %0d", test_name, gpio_out);
            else begin
                $display("[FAIL] %s: Expected GPIO = 0x%08X, got 0x%08X", test_name, expected, gpio_out);
                test_ok = 0;
            end
        end
    endtask

endmodule