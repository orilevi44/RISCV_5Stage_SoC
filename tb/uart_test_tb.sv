`timescale 1ns/1ps

module uart_test_tb ();

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
    // Hex file is passed at runtime: +HEX_FILE=sim/hex/alu.hex
    // -------------------------------------------------------------------------
    initial begin
        string hex_file;
        $dumpfile("sim/waves.fst");
        $dumpvars(0, uart_test_tb);
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
        repeat (200) @(posedge clk);
        if ($value$plusargs("HEX_FILE=%s", hex_file))
            $readmemh(hex_file, uut.u_rom.mem);
        else begin
            $display("[ERROR] No HEX_FILE provided. Use +HEX_FILE=sim/hex/alu.hex");
            $finish;
        end
        repeat (20) @(posedge clk);
        #2 rst_n = 1;
    end

    // -------------------------------------------------------------------------
    // MAIN TEST SEQUENCE 
    // -------------------------------------------------------------------------

    initial begin
        logic [7:0] recived_char;

        wait (rst_n == 1); 
        repeat (200) @(posedge clk);   // let CPU settle after reset

        $display("===========================================");
        $display("        UART Test");
        $display("===========================================");


        receive_uart_byte(recived_char);
        
        if (recived_char == 8'h4F) // ASCII 'O'
            $display("[PASS] Received expected UART byte: 0x%02X ('%c')", recived_char, recived_char);
        else begin
            $display("[FAIL] UART Test: Expected 0x4F ('O'), got 0x%02X", recived_char);
            test_ok = 0;
        end
            
        receive_uart_byte(recived_char);
        
        if (recived_char == 8'h4B) // ASCII 'K'
            $display("[PASS] Received expected UART byte: 0x%02X ('%c')", recived_char, recived_char);
        else begin
            $display("[FAIL] UART Test: Expected 0x4B ('K'), got 0x%02X", recived_char);
            test_ok = 0;
        end
        
        $display("-------------------------------------------");
        if (test_ok)
            $display("  RESULT:  ALL TESTS PASSED ");
        else
            $display("  RESULT:  ONE OR MORE TESTS FAILED ");
        $display("===========================================");
        
        $finish;
    end



    task automatic receive_uart_byte;
        output [7:0] rx_data; 
        integer i;
        begin
            
            wait (uart_tx == 1'b0);
            
            #40;
            
            for (i = 0; i < 8; i = i + 1) begin
                #80; 
                rx_data[i] = uart_tx; 
            end
            
    
            #80; 
            if (uart_tx !== 1'b1) begin
                $display("[FAIL] UART Framing Error! Stop bit not found.");
                test_ok = 0;
            end
        end
    endtask
endmodule