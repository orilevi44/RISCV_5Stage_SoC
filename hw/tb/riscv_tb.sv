`timescale 1ns / 1ps

// FIX: Renamed from soc_tb → riscv_tb to avoid module-name collision with
// tb/soc_tb.sv.  Both files define module soc_tb when compiled together via
// iverilog, which causes a "duplicate module" elaboration error.
module riscv_tb();

    // --- Simulation Signals ---
    logic clk;
    logic rst_n;
    logic [31:0] gpio_out;
    // FIX: Add UART wires so soc_top's UART ports are properly connected.
    // Leaving soc_uart_rx unconnected drives 1'bZ into the RX synchronizer,
    // producing X propagation through the UART RX FSM.
    logic uart_tx_mon;   // monitor: observe what the SoC transmits
    logic uart_rx_drv;   // driver : inject serial bytes into the SoC

    // --- Instantiate the FULL SoC ---
    // This is the Top Level we built that contains Core, Bus, RAM and GPIO
    soc_top uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .soc_gpio_out (gpio_out),
        .soc_uart_tx  (uart_tx_mon),   // FIX: connect TX output
        .soc_uart_rx  (uart_rx_drv)    // FIX: connect RX input
    );

    // --- Clock Generation (100MHz) ---
    always #5 clk = ~clk;

    // --- Simulation Control & Memory Loading ---
    initial begin
        // 1. Initialize signals
        clk = 0;
        rst_n = 0;
        uart_rx_drv = 1'b1; // FIX: drive UART RX idle-high (prevents X in RX FSM)

        // 2. Load the Program directly into the SoC's ROM
        // We use the hierarchical path to reach the memory array inside rom_model
        $readmemh("sim/program.hex", uut.u_rom.mem);
        $display("[TB] SoC ROM loaded successfully.");

        // 3. Setup Waveform Dumping
        $dumpfile("sim/waves.fst");
        $dumpvars(0, riscv_tb);

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