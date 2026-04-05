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

    // --- 4. Waveform Generation ---
    // This block tells Icarus Verilog to record everything for GTKWave
    initial begin
        $dumpfile("sim/waves.fst");
        $dumpvars(0, soc_tb);
    end

    // --- 5. Hierarchical Spying (UART & CSR) ---
    logic        spy_uart_we;
    logic        spy_uart_sel;
    logic [31:0] spy_bus_wdata;
    
    // Tap into the System Bus for UART monitoring
    assign spy_uart_we   = uut.uart_we;
    assign spy_uart_sel  = uut.uart_sel;
    assign spy_bus_wdata = uut.data_wdata;

    // Tap into the CPU's Execute stage to watch CSR reads
    logic        spy_csr_en;
    logic [31:0] spy_csr_rdata;
    assign spy_csr_en    = uut.u_core.u_execute_stage.ex_csr_en;
    assign spy_csr_rdata = uut.u_core.u_execute_stage.ex_csr_rdata;

    // --- 6. Verification Logic ---
    logic [7:0] char_history [0:15]; 
    int char_count = 0;
    
    initial begin
        for (int i = 0; i < 16; i++) char_history[i] = 8'h00;
        
        forever @(posedge clk) begin
            if (rst_n) begin
                // A. CSR Read Monitor
                // If a CSR is being read in the EX stage, print its value.
                if (spy_csr_en) begin
                    $display("[MONITOR] CSR Read Detected. Value retrieved: %0d", spy_csr_rdata);
                end

                // B. UART Output Monitor
                if (spy_uart_we && spy_uart_sel) begin
                    if (char_count < 16) begin
                        char_history[char_count] = spy_bus_wdata[7:0];
                        char_count = char_count + 1;
                    end
                    // Print character immediately to console
                    $write("%c", spy_bus_wdata[7:0]);
                end

                // C. Detect End of Program (Parking Loop)
                if (uut.u_core.actual_jump && (uut.u_core.final_branch_addr == (uut.u_core.ex_pc - 4))) begin
                    $display("\n\n**************************************************");
                    $display("      CSR PERFORMANCE TEST SUMMARY");
                    $display("**************************************************");
                    $write("  CPU Output: ");
                    for (int i = 0; i < char_count; i++) $write("%c", char_history[i]);
                    $display("");
                    
                    if (char_count >= 4 && char_history[0] == 8'h50 && char_history[1] == 8'h41) begin
                        $display("  RESULT: [SUCCESS] - CSR Counters & Logic passed! 🎉");
                    end else begin
                        $display("  RESULT: [FAILURE] - The CSR values did not change correctly.");
                    end
                    $display("**************************************************\n");
                    $finish;
                end
            end
        end
    end

    // --- 7. Safety Timeout ---
    initial begin 
        #2000000; 
        $display("\n[TIMEOUT] Simulation exceeded time limit. Check for stalls."); 
        $finish; 
    end

endmodule