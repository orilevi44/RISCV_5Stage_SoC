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

    // Clock Generator (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // Test Sequence
    initial begin
        rst_n = 0;
        soc_uart_rx = 1; 
        
        #100;
        rst_n = 1; // שחרור ה-Reset
        $display("[TB INFO] Reset released! CPU is running firmware...");
        
        // הדפסה אוטומטית ללוג בכל פעם שה-GPIO משתנה
        $monitor("[GPIO WATCH] Time = %0t | GPIO Out (Decimal) = %0d", $time, soc_gpio_out);
        
        // המתנה של 2ms כדי לאפשר ל-CPU לבצע את כל הבדיקות בפירוש ה-GPIO
        #2000000; // 2 ms @ 100 MHz
        
        $display("[TB INFO] Simulation Finished.");
        $stop;
    end

endmodule