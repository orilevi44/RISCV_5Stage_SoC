`timescale 1ns / 1ps

module soc_tb();
    // Signals
    logic clk, rst_n, uart_tx;
    logic [31:0] gpio_out;

    // 1. Instantiate SoC
    soc_top uut (.clk(clk), .rst_n(rst_n), .soc_gpio_out(gpio_out), .soc_uart_tx(uart_tx));

    // 2. Instantiate UART Monitor
    uart_monitor #(.CLK_FREQ(100_000_000), .BAUD_RATE(115200)) u_uart_mon (
        .clk(clk),
        .uart_txd(uart_tx)
    );

    // 3. Instantiate CPU Monitor (Internal probing)
    cpu_monitor u_cpu_mon (
        .clk(clk),
        .rst_n(rst_n),
        .pc(uut.u_core.if_pc),
        .instr(uut.u_core.id_inst),
        .alu_res(uut.u_core.ex_alu_res),
        .uart_busy(uut.u_uart.tx_busy)
    );

    // 4. Clock and Reset Logic
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        $readmemh("sim/program.hex", uut.u_rom.mem);
        repeat (10) @(posedge clk);
        #2 rst_n = 1;
        
        // Timeout
        #1000000;
        $display("\n[TIMEOUT]");
        $finish;
    end

    // For GTKWave simulation tool
    initial begin
    $dumpfile("sim/waves.fst"); 
    $dumpvars(0, soc_tb);       
    end

    // End-of-Program Detection & Scoreboard
    initial begin
        forever @(negedge clk) begin
            if (uut.u_core.id_inst == 32'h0000006f) begin
                $display("\n[MONITOR] End of program reached. Waiting for UART to flush...");
                
                repeat (20000) @(posedge clk); 
                
                // Scoreboard
                $display("\n===========================================");
                if (gpio_out === 32'h00000042) begin
                    $display("   STATUS: TEST PASSED! (GPIO is 0x42)     ");
                end else begin
                    $display("   STATUS: TEST FAILED! Expected 0x42, Got %h", gpio_out);
                end
                $display("===========================================\n");
                
                $finish; 
            end
        end
    end

endmodule