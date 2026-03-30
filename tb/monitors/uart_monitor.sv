/**
 * Synchronous UART Monitor
 * Uses clock cycles instead of time delays for perfect synchronization.
 */
`timescale 1ns / 1ps

module uart_monitor #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input logic clk,
    input logic uart_txd
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    initial begin
        logic [7:0] char_rx;
        $display("[MONITOR] UART Monitor initialized (%0d baud)", BAUD_RATE);
        
        forever begin
            @(negedge uart_txd); 
            
            repeat (CLKS_PER_BIT + (CLKS_PER_BIT / 2)) @(posedge clk);
            
            // קורא את 8 ביטי הנתונים (LSB first)
            for (int i = 0; i < 8; i++) begin
                char_rx[i] = uart_txd;
                repeat (CLKS_PER_BIT) @(posedge clk); 
            end
            
            $display("\n[UART RX] ----> Received Character: '%c' (Hex: %h) <----", char_rx, char_rx);
            
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    end
endmodule