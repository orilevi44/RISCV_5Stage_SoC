`timescale 1ns / 1ps

module soc_tb(); // Changed name to soc_tb to match our SoC project

    // --- Simulation Signals ---
    logic clk;
    logic rst_n;
    logic [31:0] gpio_out;

    // --- Instantiate the FULL SoC ---
    // This is the Top Level we built that contains Core, Bus, RAM and GPIO
    soc_top uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .soc_gpio_out (gpio_out)
    );

    // --- Clock Generation (100MHz) ---
    always #5 clk = ~clk;

    // --- Simulation Control & Memory Loading ---
    initial begin
        // 1. Initialize signals
        clk = 0;
        rst_n = 0;

        // 2. Load the Program directly into the SoC's ROM
        // We use the hierarchical path to reach the memory array inside rom_model
        $readmemh("sim/program.hex", uut.u_rom.mem);
        $display("[TB] SoC ROM loaded successfully.");

        // 3. Setup Waveform Dumping
        $dumpfile("sim/waves.fst");
        $dumpvars(0, soc_tb);

        // 4. Reset Sequence
        #20 rst_n = 1; 
        
        // 5. Run simulation
        #2000;

        $display("Simulation finished. Final GPIO state: %h", gpio_out);
        $finish;
    end

    // --- SoC Performance & Debug Monitor ---
    // This script prints the internal state to the terminal every clock cycle
    

endmodule