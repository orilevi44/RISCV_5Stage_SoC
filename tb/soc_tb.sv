`timescale 1ns / 1ps

/**
 * SoC Testbench - RV32I Validation
 * --------------------------------
 * This testbench spies on the System Bus to capture UART transmissions
 * and automatically verifies if the CPU logic is functioning correctly.
 */
module soc_tb();
    // --- 1. Signals ---
    logic clk, rst_n, uart_tx;
    logic [31:0] gpio_out;

    // --- 2. Instantiate SoC (Device Under Test) ---
    soc_top uut (
        .clk(clk), 
        .rst_n(rst_n), 
        .soc_gpio_out(gpio_out), 
        .soc_uart_tx(uart_tx)
    );

    // --- 3. Clock & Reset Generation ---
    initial begin 
        clk = 0; 
        forever #5 clk = ~clk; // 100MHz Clock
    end

    initial begin
        rst_n = 0;
        // Initialize ROM with NOPs to prevent 'X' states
        for (int i = 0; i < 1024; i++) uut.u_rom.mem[i] = 32'h00000013;
        
        // Load the validation program
        $readmemh("sim/program.hex", uut.u_rom.mem);
        
        repeat (10) @(posedge clk);
        #2 rst_n = 1;
        $display("\n[TB] System Reset Released. Validation Started...");
    end

    // --- 4. Hierarchical Spying ---
    // We create local wires to tap into the internal SoC bus signals.
    // This avoids "Part Select" errors in some simulators.
    logic        spy_uart_we;
    logic        spy_uart_sel;
    logic [31:0] spy_bus_wdata;

    assign spy_uart_we   = uut.uart_we;
    assign spy_uart_sel  = uut.uart_sel;
    assign spy_bus_wdata = uut.data_wdata;

    // --- 5. UART Output Collector ---
    // Captures characters sent by the CPU to the UART register.
    logic [7:0] char_history [0:15]; 
    int char_count = 0;
    
    initial begin
        for (int i = 0; i < 16; i++) char_history[i] = 8'h00;
        
        forever @(posedge clk) begin
            if (rst_n) begin
                // Monitor Bus writes to the UART address space
                if (spy_uart_we && spy_uart_sel) begin
                    if (char_count < 16) begin
                        char_history[char_count] = spy_bus_wdata[7:0];
                        char_count = char_count + 1;
                    end
                    // Print character immediately to console
                    $write("%c", spy_bus_wdata[7:0]);
                end

                // Detect End of Program (Parking Loop)
            
                // Detection of Program End (Parking Loop)
                if (uut.u_core.actual_jump && (uut.u_core.final_branch_addr == (uut.u_core.ex_pc - 4))) begin
                    $display("\n\n**************************************************");
                    $display("      FINAL RV32I COMPLIANCE SUMMARY");
                    $display("**************************************************");
                    $write("  CPU Output: ");
                    for (int i = 0; i < char_count; i++) $write("%c", char_history[i]);
                    $display("");
                    
                    if (char_count >= 4 && char_history[0] == 8'h50 && char_history[1] == 8'h41) begin
                        $display("  RESULT: [SUCCESS] - LB/SB and Forwarding are OK! 🎉");
                    end else begin
                        $display("  RESULT: [FAILURE] - Mismatch in data or branch logic.");
                    end
                    $display("**************************************************\n");
                    $finish;
                end
            end
        end
    end

    // --- 6. Safety Timeout ---
    initial begin 
        #2000000; 
        $display("\n[TIMEOUT] Simulation exceeded time limit. Check for stalls."); 
        $finish; 
    end

endmodule